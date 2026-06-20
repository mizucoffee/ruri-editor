//
//  SymbolNavigationService.swift
//  ruri
//

import CodeEditLanguages
import Foundation
import SwiftTreeSitter

nonisolated struct SymbolNavigationRequest: Equatable, Sendable {
    let projectURL: URL
    let fileURL: URL
    let text: String
    let utf16Offset: Int
}

nonisolated struct SymbolNavigationOpenDocument: Equatable, Sendable {
    let url: URL
    let text: String
}

nonisolated struct SymbolNavigationTarget: Equatable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case type
        case method
        case function
        case property
        case field
        case constructor
        case usage
    }

    let url: URL
    let range: TextRange
    let name: String
    let kind: Kind
}

nonisolated enum SymbolNavigationResolution: Equatable, Sendable {
    case implementation(SymbolNavigationTarget)
    case references([SymbolNavigationTarget])
}

nonisolated struct SymbolNavigationHoverTarget: Equatable, Sendable {
    let sourceRange: TextRange
}

@MainActor
final class SymbolNavigationService {
    var statusDidChange: ((SymbolIndexStatusState) -> Void)?

    private let worker = SymbolNavigationWorker()
    private var indexesByProjectURL: [URL: SymbolProjectIndex] = [:]
    private var statusByProjectURL: [URL: SymbolIndexStatusState] = [:]
    private var indexingTasksByProjectURL: [URL: Task<Void, Never>] = [:]
    private var indexingRequestIDsByProjectURL: [URL: UUID] = [:]
    private var activeProjectURL: URL?

    deinit {
        MainActor.assumeIsolated {
            indexingTasksByProjectURL.values.forEach { $0.cancel() }
        }
    }

    func currentStatus(for projectURL: URL?) -> SymbolIndexStatusState {
        activeProjectURL = projectURL?.standardizedFileURL
        return statusForActiveProject()
    }

    func stopIndexing(for projectURL: URL) {
        let projectURL = projectURL.standardizedFileURL
        indexingTasksByProjectURL.removeValue(forKey: projectURL)?.cancel()
        indexingRequestIDsByProjectURL.removeValue(forKey: projectURL)
        indexesByProjectURL.removeValue(forKey: projectURL)
        statusByProjectURL.removeValue(forKey: projectURL)

        if activeProjectURL == projectURL {
            activeProjectURL = nil
        }

        publishStatusForActiveProject()
    }

    func startIndexing(projectURL: URL) {
        let projectURL = projectURL.standardizedFileURL
        let requestID = UUID()
        indexingTasksByProjectURL.removeValue(forKey: projectURL)?.cancel()
        indexingRequestIDsByProjectURL[projectURL] = requestID
        statusByProjectURL[projectURL] = .indexing
        publishStatusForActiveProject()

        indexingTasksByProjectURL[projectURL] = Task { [weak self] in
            guard let self else { return }
            do {
                let index = try await worker.indexProject(projectURL: projectURL)
                await MainActor.run {
                    guard self.indexingRequestIDsByProjectURL[projectURL] == requestID else { return }
                    self.indexesByProjectURL[projectURL] = index
                    self.indexingTasksByProjectURL.removeValue(forKey: projectURL)
                    self.indexingRequestIDsByProjectURL.removeValue(forKey: projectURL)
                    self.statusByProjectURL[projectURL] = .ready(
                        symbolCount: index.symbolCount,
                        fileCount: index.fileCount
                    )
                    self.publishStatusForActiveProject()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.indexingRequestIDsByProjectURL[projectURL] == requestID else { return }
                    self.indexingTasksByProjectURL.removeValue(forKey: projectURL)
                    self.indexingRequestIDsByProjectURL.removeValue(forKey: projectURL)
                    self.statusByProjectURL[projectURL] = .failed(message: error.localizedDescription)
                    self.publishStatusForActiveProject()
                }
            }
        }
    }

    func ensureIndexing(projectURL: URL) {
        let projectURL = projectURL.standardizedFileURL

        if indexingTasksByProjectURL[projectURL] != nil {
            statusByProjectURL[projectURL] = .indexing
            publishStatusForActiveProject()
            return
        }

        if indexesByProjectURL[projectURL] != nil {
            updateReadyStatus(for: projectURL)
            return
        }

        startIndexing(projectURL: projectURL)
    }

    func updateFile(projectURL: URL, fileURL: URL, text: String) async {
        let projectURL = projectURL.standardizedFileURL
        let fileURL = fileURL.standardizedFileURL
        guard indexesByProjectURL[projectURL] != nil else { return }

        let fileIndex = await worker.indexFile(fileURL: fileURL, projectURL: projectURL, text: text)
        if let fileIndex {
            indexesByProjectURL[projectURL]?.filesByURL[fileURL] = fileIndex
        } else {
            indexesByProjectURL[projectURL]?.filesByURL.removeValue(forKey: fileURL)
        }
        updateReadyStatus(for: projectURL)
    }

    func refreshChangedFiles(
        projectURL: URL,
        changedPaths: Set<String>,
        startIndexingIfMissing: Bool = true
    ) async {
        let projectURL = projectURL.standardizedFileURL
        guard let currentIndex = indexesByProjectURL[projectURL] else {
            if startIndexingIfMissing {
                startIndexing(projectURL: projectURL)
            }
            return
        }

        let refreshedIndex = await worker.refreshChangedFiles(
            projectURL: projectURL,
            changedPaths: changedPaths,
            currentIndex: currentIndex
        )
        indexesByProjectURL[projectURL] = refreshedIndex
        updateReadyStatus(for: projectURL)
    }

    func resolveImplementationOrReferences(
        _ request: SymbolNavigationRequest,
        openDocuments: [SymbolNavigationOpenDocument]
    ) async -> SymbolNavigationResolution? {
        let projectURL = request.projectURL.standardizedFileURL
        activeProjectURL = projectURL

        let baseIndex = indexesByProjectURL[projectURL] ?? SymbolProjectIndex(projectURL: projectURL)
        let overlayTexts = Dictionary(
            uniqueKeysWithValues: openDocuments.compactMap { document -> (URL, String)? in
                guard SymbolDocumentLanguage.language(for: document.url) != nil else { return nil }
                return (document.url.standardizedFileURL, document.text)
            }
        )
        let overlayFiles = await worker.indexOpenDocuments(openDocuments, projectURL: projectURL)
        return await worker.resolve(
            request: request,
            baseIndex: baseIndex,
            overlayFiles: overlayFiles,
            overlayTexts: overlayTexts
        )
    }

    func resolveHoverTarget(
        _ request: SymbolNavigationRequest,
        openDocuments: [SymbolNavigationOpenDocument]
    ) async -> SymbolNavigationHoverTarget? {
        let projectURL = request.projectURL.standardizedFileURL
        activeProjectURL = projectURL

        let baseIndex = indexesByProjectURL[projectURL] ?? SymbolProjectIndex(projectURL: projectURL)
        let overlayFiles = await worker.indexOpenDocuments(openDocuments, projectURL: projectURL)
        return await worker.resolveHoverTarget(
            request: request,
            baseIndex: baseIndex,
            overlayFiles: overlayFiles
        )
    }

    private func updateReadyStatus(for projectURL: URL) {
        guard let index = indexesByProjectURL[projectURL] else {
            statusByProjectURL[projectURL] = .inactive
            publishStatusForActiveProject()
            return
        }

        statusByProjectURL[projectURL] = .ready(
            symbolCount: index.symbolCount,
            fileCount: index.fileCount
        )
        publishStatusForActiveProject()
    }

    private func statusForActiveProject() -> SymbolIndexStatusState {
        guard let activeProjectURL else { return .inactive }
        return statusByProjectURL[activeProjectURL] ?? .inactive
    }

    private func publishStatusForActiveProject() {
        statusDidChange?(statusForActiveProject())
    }
}

nonisolated private struct SymbolFileIndex: Equatable, Sendable {
    let url: URL
    let language: SymbolDocumentLanguage
    let packageName: String?
    let imports: [String]
    var symbols: [SymbolNavigationTarget]
}

nonisolated private struct SymbolProjectIndex: Equatable, Sendable {
    let projectURL: URL
    var filesByURL: [URL: SymbolFileIndex] = [:]

    var symbolCount: Int {
        filesByURL.values.reduce(0) { $0 + $1.symbols.count }
    }

    var fileCount: Int {
        filesByURL.count
    }
}

nonisolated private enum SymbolDocumentLanguage: Sendable {
    case java
    case kotlin

    static func language(for url: URL) -> SymbolDocumentLanguage? {
        switch url.pathExtension.lowercased() {
        case "java":
            .java
        case "kt", "kts":
            .kotlin
        default:
            nil
        }
    }

    var codeLanguage: CodeLanguage {
        switch self {
        case .java:
            .java
        case .kotlin:
            .kotlin
        }
    }
}

private actor SymbolNavigationWorker {
    private let fileManager = FileManager.default

    func indexProject(projectURL: URL) throws -> SymbolProjectIndex {
        let projectURL = projectURL.standardizedFileURL
        var index = SymbolProjectIndex(projectURL: projectURL)

        for fileURL in supportedFileURLs(projectURL: projectURL) {
            try Task.checkCancellation()
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
                  let fileIndex = indexFile(fileURL: fileURL, projectURL: projectURL, text: text) else {
                continue
            }

            index.filesByURL[fileURL.standardizedFileURL] = fileIndex
        }

        return index
    }

    func indexFile(fileURL: URL, projectURL: URL, text: String) -> SymbolFileIndex? {
        let fileURL = fileURL.standardizedFileURL
        guard let language = SymbolDocumentLanguage.language(for: fileURL),
              let tree = parse(text: text, language: language),
              let rootNode = tree.rootNode else {
            return nil
        }

        let packageName = packageName(in: text, language: language)
        let imports = importNames(in: text, language: language)
        var symbols: [SymbolNavigationTarget] = []
        collectSymbols(
            from: rootNode,
            text: text,
            url: fileURL,
            language: language,
            symbols: &symbols
        )

        return SymbolFileIndex(
            url: fileURL,
            language: language,
            packageName: packageName,
            imports: imports,
            symbols: uniqueSorted(symbols)
        )
    }

    func refreshChangedFiles(
        projectURL: URL,
        changedPaths: Set<String>,
        currentIndex: SymbolProjectIndex
    ) -> SymbolProjectIndex {
        var index = currentIndex
        let changedURLs = changedSupportedURLs(projectURL: projectURL, changedPaths: changedPaths)

        guard !changedURLs.isEmpty else {
            return index
        }

        let changedDirectories = changedURLs.filter { url in
            isDirectory(url) || SymbolDocumentLanguage.language(for: url) == nil
        }
        for directoryURL in changedDirectories {
            index.filesByURL = index.filesByURL.filter { url, _ in
                !isDescendantOrSame(url, of: directoryURL)
            }
        }

        for url in changedURLs where !isDirectory(url) {
            index.filesByURL.removeValue(forKey: url.standardizedFileURL)
        }

        let filesToIndex = changedURLs.flatMap { url -> [URL] in
            if isDirectory(url) {
                return supportedFileURLs(projectURL: url.standardizedFileURL)
            }

            return SymbolDocumentLanguage.language(for: url) == nil ? [] : [url.standardizedFileURL]
        }

        for fileURL in Set(filesToIndex) {
            guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)),
                  let text = try? String(contentsOf: fileURL, encoding: .utf8),
                  let fileIndex = indexFile(fileURL: fileURL, projectURL: projectURL, text: text) else {
                continue
            }

            index.filesByURL[fileURL.standardizedFileURL] = fileIndex
        }

        return index
    }

    func indexOpenDocuments(
        _ documents: [SymbolNavigationOpenDocument],
        projectURL: URL
    ) -> [URL: SymbolFileIndex] {
        var indexes: [URL: SymbolFileIndex] = [:]

        for document in documents {
            let url = document.url.standardizedFileURL
            guard let fileIndex = indexFile(fileURL: url, projectURL: projectURL, text: document.text) else {
                continue
            }

            indexes[url] = fileIndex
        }

        return indexes
    }

    func resolve(
        request: SymbolNavigationRequest,
        baseIndex: SymbolProjectIndex,
        overlayFiles: [URL: SymbolFileIndex],
        overlayTexts: [URL: String]
    ) async -> SymbolNavigationResolution? {
        let fileURL = request.fileURL.standardizedFileURL
        let mergedIndex = merged(baseIndex: baseIndex, overlayFiles: overlayFiles)
        guard let identifier = identifier(at: request.utf16Offset, in: request.text),
              !identifier.name.isEmpty else {
            return nil
        }

        let selectedRange = TextRange(location: identifier.range.location, length: identifier.range.length)
        let selectedFile = mergedIndex.filesByURL[fileURL]
        let selectedSymbol = selectedFile?.symbols.first { symbol in
            symbol.name == identifier.name && symbol.range.nsRange.intersectsOrTouches(selectedRange.nsRange)
        }

        if selectedSymbol != nil {
            let targets = await usageTargets(
                named: identifier.name,
                excludingDefinitionRanges: definitionRangesByURL(named: identifier.name, in: mergedIndex),
                index: mergedIndex,
                overlayTexts: overlayTexts
            )
            return .references(targets)
        }

        let candidates = definitionCandidates(
            named: identifier.name,
            requestFileURL: fileURL,
            currentFile: selectedFile,
            index: mergedIndex
        )

        if candidates.count == 1,
           let target = candidates.first {
            return .implementation(target)
        }

        if !candidates.isEmpty {
            return .references(candidates)
        }

        return nil
    }

    func resolveHoverTarget(
        request: SymbolNavigationRequest,
        baseIndex: SymbolProjectIndex,
        overlayFiles: [URL: SymbolFileIndex]
    ) async -> SymbolNavigationHoverTarget? {
        let fileURL = request.fileURL.standardizedFileURL
        let mergedIndex = merged(baseIndex: baseIndex, overlayFiles: overlayFiles)
        guard let identifier = identifier(at: request.utf16Offset, in: request.text),
              !identifier.name.isEmpty else {
            return nil
        }

        let selectedRange = TextRange(location: identifier.range.location, length: identifier.range.length)
        let selectedFile = mergedIndex.filesByURL[fileURL]
        let selectedSymbol = selectedFile?.symbols.first { symbol in
            symbol.name == identifier.name && symbol.range.nsRange.intersectsOrTouches(selectedRange.nsRange)
        }

        if selectedSymbol != nil {
            return SymbolNavigationHoverTarget(sourceRange: selectedRange)
        }

        let candidates = definitionCandidates(
            named: identifier.name,
            requestFileURL: fileURL,
            currentFile: selectedFile,
            index: mergedIndex
        )

        guard !candidates.isEmpty else { return nil }
        return SymbolNavigationHoverTarget(sourceRange: selectedRange)
    }

    private func parse(text: String, language: SymbolDocumentLanguage) -> MutableTree? {
        guard let treeSitterLanguage = language.codeLanguage.language else { return nil }

        let parser = Parser()
        do {
            try parser.setLanguage(treeSitterLanguage)
        } catch {
            return nil
        }

        return parser.parse(text)
    }

    private func collectSymbols(
        from node: Node,
        text: String,
        url: URL,
        language: SymbolDocumentLanguage,
        symbols: inout [SymbolNavigationTarget]
    ) {
        if let symbol = symbol(from: node, text: text, url: url, language: language) {
            symbols.append(symbol)
        }

        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index) else { continue }
            collectSymbols(from: child, text: text, url: url, language: language, symbols: &symbols)
        }
    }

    private func symbol(
        from node: Node,
        text: String,
        url: URL,
        language: SymbolDocumentLanguage
    ) -> SymbolNavigationTarget? {
        switch language {
        case .java:
            return javaSymbol(from: node, text: text, url: url)
        case .kotlin:
            return kotlinSymbol(from: node, text: text, url: url)
        }
    }

    private func javaSymbol(from node: Node, text: String, url: URL) -> SymbolNavigationTarget? {
        guard let nodeType = node.nodeType else { return nil }

        switch nodeType {
        case "class_declaration", "interface_declaration", "enum_declaration", "record_declaration":
            return symbolTarget(nameNode: nameNode(in: node), kind: .type, text: text, url: url)
        case "method_declaration":
            return symbolTarget(nameNode: nameNode(in: node), kind: .method, text: text, url: url)
        case "constructor_declaration":
            return symbolTarget(nameNode: nameNode(in: node), kind: .constructor, text: text, url: url)
        case "variable_declarator":
            guard ancestor(of: node, hasType: "field_declaration") else { return nil }
            return symbolTarget(nameNode: nameNode(in: node), kind: .field, text: text, url: url)
        default:
            return nil
        }
    }

    private func kotlinSymbol(from node: Node, text: String, url: URL) -> SymbolNavigationTarget? {
        guard let nodeType = node.nodeType else { return nil }

        switch nodeType {
        case "class_declaration", "object_declaration":
            return symbolTarget(
                nameNode: nameNode(in: node) ?? firstDescendant(of: node, withType: "type_identifier"),
                kind: .type,
                text: text,
                url: url
            )
        case "function_declaration":
            return symbolTarget(
                nameNode: nameNode(in: node) ?? firstDescendant(of: node, withType: "simple_identifier"),
                kind: .function,
                text: text,
                url: url
            )
        case "variable_declaration":
            guard ancestor(of: node, hasType: "property_declaration")
                    || ancestor(of: node, hasType: "class_parameter") else {
                return nil
            }
            return symbolTarget(
                nameNode: nameNode(in: node) ?? firstDescendant(of: node, withType: "simple_identifier"),
                kind: .property,
                text: text,
                url: url
            )
        case "class_parameter":
            return symbolTarget(
                nameNode: nameNode(in: node) ?? firstDescendant(of: node, withType: "simple_identifier"),
                kind: .property,
                text: text,
                url: url
            )
        default:
            return nil
        }
    }

    private func symbolTarget(
        nameNode: Node?,
        kind: SymbolNavigationTarget.Kind,
        text: String,
        url: URL
    ) -> SymbolNavigationTarget? {
        guard let nameNode,
              let name = substring(in: text, range: nameNode.range),
              !name.isEmpty else {
            return nil
        }

        return SymbolNavigationTarget(
            url: url.standardizedFileURL,
            range: TextRange(location: nameNode.range.location, length: nameNode.range.length),
            name: name,
            kind: kind
        )
    }

    private func nameNode(in node: Node) -> Node? {
        if let fieldNode = node.child(byFieldName: "name") {
            return fieldNode
        }

        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index),
                  child.nodeType == "identifier"
                    || child.nodeType == "type_identifier"
                    || child.nodeType == "simple_identifier" else {
                continue
            }
            return child
        }

        return nil
    }

    private func firstDescendant(of node: Node, withType nodeType: String) -> Node? {
        if node.nodeType == nodeType {
            return node
        }

        for index in 0..<node.namedChildCount {
            guard let child = node.namedChild(at: index) else { continue }
            if let match = firstDescendant(of: child, withType: nodeType) {
                return match
            }
        }

        return nil
    }

    private func ancestor(of node: Node, hasType nodeType: String) -> Bool {
        var parent = node.parent
        while let current = parent {
            if current.nodeType == nodeType {
                return true
            }
            parent = current.parent
        }

        return false
    }

    private func merged(
        baseIndex: SymbolProjectIndex,
        overlayFiles: [URL: SymbolFileIndex]
    ) -> SymbolProjectIndex {
        var index = baseIndex
        for (url, fileIndex) in overlayFiles {
            index.filesByURL[url.standardizedFileURL] = fileIndex
        }
        return index
    }

    private func definitionCandidates(
        named name: String,
        requestFileURL: URL,
        currentFile: SymbolFileIndex?,
        index: SymbolProjectIndex
    ) -> [SymbolNavigationTarget] {
        let candidates = index.filesByURL.values.flatMap(\.symbols).filter { $0.name == name }
        guard candidates.count > 1 else { return candidates }

        let currentPackage = currentFile?.packageName
        let imports = currentFile?.imports ?? []
        let explicitImports = Set(imports.filter { !$0.hasSuffix(".*") })
        let wildcardPackages = imports
            .filter { $0.hasSuffix(".*") }
            .map { String($0.dropLast(2)) }

        let rankedCandidates = candidates
            .map { target in
                (
                    target: target,
                    rank: candidateRank(
                        target,
                        requestFileURL: requestFileURL,
                        currentPackage: currentPackage,
                        explicitImports: explicitImports,
                        wildcardPackages: wildcardPackages,
                        index: index
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }

                let lhsPath = normalizedPath(lhs.target.url)
                let rhsPath = normalizedPath(rhs.target.url)
                if lhsPath != rhsPath {
                    return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
                }

                return lhs.target.range.location < rhs.target.range.location
            }

        if let first = rankedCandidates.first,
           rankedCandidates.dropFirst().allSatisfy({ $0.rank > first.rank }) {
            return [first.target]
        }

        return rankedCandidates.map { $0.target }
    }

    private func candidateRank(
        _ target: SymbolNavigationTarget,
        requestFileURL: URL,
        currentPackage: String?,
        explicitImports: Set<String>,
        wildcardPackages: [String],
        index: SymbolProjectIndex
    ) -> Int {
        if FileURLRewriter.urlsMatch(target.url, requestFileURL) {
            return 0
        }

        guard let targetFile = index.filesByURL[target.url.standardizedFileURL] else {
            return 5
        }

        if let targetPackage = targetFile.packageName,
           explicitImports.contains("\(targetPackage).\(target.name)") {
            return 1
        }

        if let targetPackage = targetFile.packageName,
           wildcardPackages.contains(targetPackage) {
            return 2
        }

        if let currentPackage,
           currentPackage == targetFile.packageName {
            return 3
        }

        return 4
    }

    private func usageTargets(
        named name: String,
        excludingDefinitionRanges definitionRangesByURL: [URL: Set<TextRange>],
        index: SymbolProjectIndex,
        overlayTexts: [URL: String]
    ) async -> [SymbolNavigationTarget] {
        var targets: [SymbolNavigationTarget] = []

        for fileURL in index.filesByURL.keys.sorted(by: { normalizedPath($0) < normalizedPath($1) }) {
            let text: String?
            if let overlayText = overlayTexts[fileURL] {
                text = overlayText
            } else {
                text = try? String(contentsOf: fileURL, encoding: .utf8)
            }

            guard let text else { continue }
            let excludedRanges = definitionRangesByURL[fileURL] ?? []
            for range in identifierRanges(named: name, in: text) where !excludedRanges.contains(range) {
                targets.append(SymbolNavigationTarget(
                    url: fileURL,
                    range: range,
                    name: name,
                    kind: .usage
                ))
            }
        }

        return uniqueSorted(targets)
    }

    private func definitionRangesByURL(
        named name: String,
        in index: SymbolProjectIndex
    ) -> [URL: Set<TextRange>] {
        var rangesByURL: [URL: Set<TextRange>] = [:]
        for fileIndex in index.filesByURL.values {
            for symbol in fileIndex.symbols where symbol.name == name {
                rangesByURL[fileIndex.url, default: []].insert(symbol.range)
            }
        }
        return rangesByURL
    }

    private func supportedFileURLs(projectURL: URL) -> [URL] {
        let projectURL = projectURL.standardizedFileURL
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isHiddenKey,
            .isRegularFileKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        var gitIgnoreMatcher = GitIgnoreMatcher(rootURL: projectURL)

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }

            let name = fileURL.lastPathComponent
            let isDirectory = values.isDirectory == true

            if values.isHidden == true || name.hasPrefix(".") {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isDirectory {
                if Self.skippedDirectoryNames.contains(name)
                    || gitIgnoreMatcher.isIgnored(fileURL, isDirectory: true) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true,
                  SymbolDocumentLanguage.language(for: fileURL) != nil,
                  !gitIgnoreMatcher.isIgnored(fileURL, isDirectory: false) else {
                continue
            }

            urls.append(fileURL.standardizedFileURL)
        }

        return urls
    }

    private func changedSupportedURLs(projectURL: URL, changedPaths: Set<String>) -> [URL] {
        guard !changedPaths.isEmpty else {
            return [projectURL.standardizedFileURL]
        }

        return changedPaths
            .map { URL(filePath: $0).standardizedFileURL }
            .filter { url in
                guard isDescendantOrSame(url, of: projectURL) else { return false }
                return isDirectory(url)
                    || SymbolDocumentLanguage.language(for: url) != nil
                    || url.pathExtension.isEmpty
            }
    }

    private func packageName(in text: String, language: SymbolDocumentLanguage) -> String? {
        let pattern: String
        switch language {
        case .java:
            pattern = #"(?m)^\s*package\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*;"#
        case .kotlin:
            pattern = #"(?m)^\s*package\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)"#
        }

        return firstCapture(in: text, pattern: pattern)
    }

    private func importNames(in text: String, language: SymbolDocumentLanguage) -> [String] {
        let pattern: String
        switch language {
        case .java:
            pattern = #"(?m)^\s*import\s+(?:static\s+)?([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_*][A-Za-z0-9_*]*)*)\s*;"#
        case .kotlin:
            pattern = #"(?m)^\s*import\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_*][A-Za-z0-9_*]*)*)(?:\s+as\s+[A-Za-z_][A-Za-z0-9_]*)?"#
        }

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let string = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: string.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return string.substring(with: match.range(at: 1))
        }
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let string = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: string.length)),
              match.numberOfRanges > 1 else {
            return nil
        }

        return string.substring(with: match.range(at: 1))
    }

    private func identifier(at utf16Offset: Int, in text: String) -> (name: String, range: NSRange)? {
        let string = text as NSString
        guard string.length > 0 else { return nil }

        var offset = min(max(0, utf16Offset), string.length)
        if offset == string.length {
            offset -= 1
        }

        if !isIdentifierCharacter(string.character(at: offset)),
           offset > 0,
           isIdentifierCharacter(string.character(at: offset - 1)) {
            offset -= 1
        }

        guard isIdentifierCharacter(string.character(at: offset)) else {
            return nil
        }

        var start = offset
        while start > 0 && isIdentifierCharacter(string.character(at: start - 1)) {
            start -= 1
        }

        var end = offset + 1
        while end < string.length && isIdentifierCharacter(string.character(at: end)) {
            end += 1
        }

        let range = NSRange(location: start, length: end - start)
        let name = string.substring(with: range)
        return (name, range)
    }

    private func identifierRanges(named name: String, in text: String) -> [TextRange] {
        guard !name.isEmpty else { return [] }

        let string = text as NSString
        var ranges: [TextRange] = []
        var searchLocation = 0

        while searchLocation < string.length {
            let searchRange = NSRange(location: searchLocation, length: string.length - searchLocation)
            let matchRange = string.range(of: name, options: [], range: searchRange)
            guard matchRange.location != NSNotFound else { break }

            let before = matchRange.location > 0 ? string.character(at: matchRange.location - 1) : nil
            let afterLocation = NSMaxRange(matchRange)
            let after = afterLocation < string.length ? string.character(at: afterLocation) : nil
            if before.map(isIdentifierCharacter) != true && after.map(isIdentifierCharacter) != true {
                ranges.append(TextRange(location: matchRange.location, length: matchRange.length))
            }

            searchLocation = max(NSMaxRange(matchRange), matchRange.location + 1)
        }

        return ranges
    }

    private func substring(in text: String, range: NSRange) -> String? {
        let string = text as NSString
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= string.length else {
            return nil
        }

        return string.substring(with: range)
    }

    private func uniqueSorted(_ targets: [SymbolNavigationTarget]) -> [SymbolNavigationTarget] {
        var seen = Set<SymbolNavigationTarget>()
        let uniqueTargets = targets.filter { seen.insert($0).inserted }
        return uniqueTargets.sorted { lhs, rhs in
            let lhsPath = normalizedPath(lhs.url)
            let rhsPath = normalizedPath(rhs.url)
            if lhsPath != rhsPath {
                return lhsPath.localizedStandardCompare(rhsPath) == .orderedAscending
            }
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            if lhs.range.length != rhs.range.length {
                return lhs.range.length < rhs.range.length
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func isIdentifierCharacter(_ character: unichar) -> Bool {
        let scalar = UnicodeScalar(Int(character))
        guard let scalar else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$"
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func isDescendantOrSame(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let candidatePath = normalizedPath(candidateURL)
        let rootPath = normalizedPath(rootURL)
        return candidatePath == rootPath || candidatePath.hasPrefix("\(rootPath)/")
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static let skippedDirectoryNames: Set<String> = [
        "build",
        ".build",
        ".gradle",
        "out",
        "target",
        "node_modules",
        "DerivedData"
    ]
}

private extension NSRange {
    nonisolated func intersectsOrTouches(_ other: NSRange) -> Bool {
        if length == 0 || other.length == 0 {
            return location == other.location
        }

        return location < NSMaxRange(other) && other.location < NSMaxRange(self)
    }
}
