//
//  SymbolNavigationService.swift
//  ruri
//

import Foundation

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

nonisolated struct SymbolNavigationTarget: Equatable, Hashable, Sendable, Codable {
    enum Kind: String, Sendable, Codable {
        case type
        case method
        case function
        case property
        case field
        case variable
        case parameter
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

nonisolated struct JavaSymbolResolverRequest: Equatable, Sendable, Codable {
    enum Command: String, Sendable, Codable {
        case resolve
        case hover
    }

    struct OpenDocument: Equatable, Sendable, Codable {
        let path: String
        let text: String
    }

    let command: Command
    let projectPath: String
    let filePath: String
    let text: String
    let utf16Offset: Int
    let openDocuments: [OpenDocument]
    let sourceRoots: [String]
    let sourceFiles: [String]
    let classpath: [String]
    let referenceLimit: Int?
}

nonisolated struct JavaSymbolResolverResponse: Equatable, Sendable, Codable {
    enum ResolutionKind: String, Sendable, Codable {
        case implementation
        case references
    }

    let resolutionKind: ResolutionKind?
    let target: SymbolNavigationTarget?
    let targets: [SymbolNavigationTarget]
    let hoverRange: TextRange?
    let needsReferenceSearch: Bool?
    let diagnostics: [String]
}

nonisolated protocol JavaSymbolResolving: Sendable {
    func resolve(_ request: JavaSymbolResolverRequest) async throws -> JavaSymbolResolverResponse
    func stop() async
}

nonisolated struct JavaSymbolResolverError: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

@MainActor
final class SymbolNavigationService {
    var statusDidChange: ((SymbolIndexStatusState) -> Void)?

    private let resolver: any JavaSymbolResolving
    private let classpathService: JavaClasspathService
    private let worker = JavaSymbolWorkspaceWorker()
    private var statusByProjectURL: [URL: SymbolIndexStatusState] = [:]
    private var sourceRootsByProjectURL: [URL: [URL]] = [:]
    private var sourceFilesByProjectURL: [URL: [URL]] = [:]
    private var indexingTasksByProjectURL: [URL: Task<Void, Never>] = [:]
    private var indexingRequestIDsByProjectURL: [URL: UUID] = [:]
    private var activeProjectURL: URL?

    init(
        resolver: (any JavaSymbolResolving)? = nil,
        classpathService: JavaClasspathService = JavaClasspathService()
    ) {
        self.resolver = resolver ?? JavaSymbolResolverClient()
        self.classpathService = classpathService
    }

    deinit {
        MainActor.assumeIsolated {
            indexingTasksByProjectURL.values.forEach { $0.cancel() }
            let resolver = resolver
            Task {
                await resolver.stop()
            }
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
        statusByProjectURL.removeValue(forKey: projectURL)
        sourceRootsByProjectURL.removeValue(forKey: projectURL)
        sourceFilesByProjectURL.removeValue(forKey: projectURL)

        Task {
            await classpathService.stopPreparing(projectURL: projectURL)
        }

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

            let summary = await worker.summary(projectURL: projectURL)
            await classpathService.prepare(projectURL: projectURL)

            await MainActor.run {
                guard self.indexingRequestIDsByProjectURL[projectURL] == requestID else { return }
                self.indexingTasksByProjectURL.removeValue(forKey: projectURL)
                self.indexingRequestIDsByProjectURL.removeValue(forKey: projectURL)
                self.sourceRootsByProjectURL[projectURL] = summary.sourceRoots
                self.sourceFilesByProjectURL[projectURL] = summary.sourceFiles
                self.statusByProjectURL[projectURL] = .ready(
                    symbolCount: summary.fileCount,
                    fileCount: summary.fileCount
                )
                self.publishStatusForActiveProject()
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

        if statusByProjectURL[projectURL] != nil {
            publishStatusForActiveProject()
            return
        }

        startIndexing(projectURL: projectURL)
    }

    func updateFile(projectURL: URL, fileURL: URL, text: String) async {
        guard Self.isJavaFile(fileURL) else { return }
        await classpathService.invalidateSourceFile(projectURL: projectURL.standardizedFileURL, fileURL: fileURL)
    }

    func refreshChangedFiles(
        projectURL: URL,
        changedPaths: Set<String>,
        startIndexingIfMissing: Bool = true
    ) async {
        let projectURL = projectURL.standardizedFileURL
        if statusByProjectURL[projectURL] == nil {
            if startIndexingIfMissing {
                startIndexing(projectURL: projectURL)
            }
            return
        }

        if changedPaths.contains(where: Self.mayAffectClasspath) {
            await classpathService.prepare(projectURL: projectURL, force: true)
        }

        let summary = await worker.summary(projectURL: projectURL)
        sourceRootsByProjectURL[projectURL] = summary.sourceRoots
        sourceFilesByProjectURL[projectURL] = summary.sourceFiles
        statusByProjectURL[projectURL] = .ready(
            symbolCount: summary.fileCount,
            fileCount: summary.fileCount
        )
        publishStatusForActiveProject()
    }

    func resolveImplementationOrReferences(
        _ request: SymbolNavigationRequest,
        openDocuments: [SymbolNavigationOpenDocument]
    ) async -> SymbolNavigationResolution? {
        guard Self.isJavaFile(request.fileURL) else { return nil }
        activeProjectURL = request.projectURL.standardizedFileURL

        do {
            let response = try await resolver.resolve(
                resolverRequest(
                    command: .resolve,
                    request: request,
                    openDocuments: openDocuments,
                    includeReferenceSearch: false,
                    referenceLimit: nil
                )
            )
            publishDiagnosticsIfNeeded(response.diagnostics, for: request.projectURL)

            let resolvedResponse: JavaSymbolResolverResponse
            if response.needsReferenceSearch == true {
                resolvedResponse = try await resolver.resolve(
                    resolverRequest(
                        command: .resolve,
                        request: request,
                        openDocuments: openDocuments,
                        includeReferenceSearch: true,
                        referenceLimit: nil
                    )
                )
                publishDiagnosticsIfNeeded(resolvedResponse.diagnostics, for: request.projectURL)
            } else {
                resolvedResponse = response
            }

            switch resolvedResponse.resolutionKind {
            case .implementation:
                guard let target = resolvedResponse.target else { return nil }
                return .implementation(target)
            case .references:
                return resolvedResponse.targets.isEmpty ? nil : .references(resolvedResponse.targets)
            case nil:
                return nil
            }
        } catch is CancellationError {
            return nil
        } catch {
            statusByProjectURL[request.projectURL.standardizedFileURL] = .failed(message: error.localizedDescription)
            publishStatusForActiveProject()
            return nil
        }
    }

    func resolveHoverTarget(
        _ request: SymbolNavigationRequest,
        openDocuments: [SymbolNavigationOpenDocument]
    ) async -> SymbolNavigationHoverTarget? {
        guard Self.isJavaFile(request.fileURL) else { return nil }
        activeProjectURL = request.projectURL.standardizedFileURL

        do {
            let response = try await resolver.resolve(
                resolverRequest(
                    command: .hover,
                    request: request,
                    openDocuments: openDocuments,
                    includeReferenceSearch: false,
                    referenceLimit: nil
                )
            )
            publishDiagnosticsIfNeeded(response.diagnostics, for: request.projectURL)

            let resolvedResponse: JavaSymbolResolverResponse
            if response.needsReferenceSearch == true {
                resolvedResponse = try await resolver.resolve(
                    resolverRequest(
                        command: .hover,
                        request: request,
                        openDocuments: openDocuments,
                        includeReferenceSearch: true,
                        referenceLimit: 1
                    )
                )
                publishDiagnosticsIfNeeded(resolvedResponse.diagnostics, for: request.projectURL)
            } else {
                resolvedResponse = response
            }

            guard let hoverRange = resolvedResponse.hoverRange else { return nil }
            return SymbolNavigationHoverTarget(sourceRange: hoverRange)
        } catch is CancellationError {
            return nil
        } catch {
            statusByProjectURL[request.projectURL.standardizedFileURL] = .failed(message: error.localizedDescription)
            publishStatusForActiveProject()
            return nil
        }
    }

    private func resolverRequest(
        command: JavaSymbolResolverRequest.Command,
        request: SymbolNavigationRequest,
        openDocuments: [SymbolNavigationOpenDocument],
        includeReferenceSearch: Bool,
        referenceLimit: Int?
    ) async -> JavaSymbolResolverRequest {
        let projectURL = request.projectURL.standardizedFileURL
        let classpath = await classpathService.classpath(projectURL: projectURL)
        let sourceRoots = sourceRoots(for: projectURL, selectedFileURL: request.fileURL)
        let sourceFiles = includeReferenceSearch ? sourceFiles(for: projectURL, selectedFileURL: request.fileURL) : []
        let javaOpenDocuments = openDocuments
            .filter { Self.isJavaFile($0.url) }
            .map {
                JavaSymbolResolverRequest.OpenDocument(
                    path: $0.url.standardizedFileURL.path(percentEncoded: false),
                    text: $0.text
                )
            }

        return JavaSymbolResolverRequest(
            command: command,
            projectPath: projectURL.path(percentEncoded: false),
            filePath: request.fileURL.standardizedFileURL.path(percentEncoded: false),
            text: request.text,
            utf16Offset: request.utf16Offset,
            openDocuments: javaOpenDocuments,
            sourceRoots: sourceRoots.map { $0.path(percentEncoded: false) },
            sourceFiles: sourceFiles.map { $0.path(percentEncoded: false) },
            classpath: classpath.map { $0.path(percentEncoded: false) },
            referenceLimit: referenceLimit
        )
    }

    private func sourceRoots(for projectURL: URL, selectedFileURL: URL) -> [URL] {
        var roots = sourceRootsByProjectURL[projectURL.standardizedFileURL] ?? []
        roots.append(projectURL.standardizedFileURL)
        roots.append(selectedFileURL.deletingLastPathComponent().standardizedFileURL)

        var seen = Set<String>()
        return roots.compactMap { url in
            let standardized = url.standardizedFileURL
            let path = standardized.path(percentEncoded: false)
            return seen.insert(path).inserted ? standardized : nil
        }
    }

    private func sourceFiles(for projectURL: URL, selectedFileURL: URL) -> [URL] {
        var files = sourceFilesByProjectURL[projectURL.standardizedFileURL] ?? []
        files.append(selectedFileURL.standardizedFileURL)

        var seen = Set<String>()
        return files.compactMap { url in
            let standardized = url.standardizedFileURL
            let path = standardized.path(percentEncoded: false)
            return seen.insert(path).inserted ? standardized : nil
        }
    }

    private func publishDiagnosticsIfNeeded(_ diagnostics: [String], for projectURL: URL) {
        guard !diagnostics.isEmpty else { return }
        statusByProjectURL[projectURL.standardizedFileURL] = .failed(message: diagnostics.joined(separator: "\n"))
        publishStatusForActiveProject()
    }

    private func statusForActiveProject() -> SymbolIndexStatusState {
        guard let activeProjectURL else { return .inactive }
        return statusByProjectURL[activeProjectURL] ?? .inactive
    }

    private func publishStatusForActiveProject() {
        statusDidChange?(statusForActiveProject())
    }

    private static func isJavaFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "java"
    }

    private static func mayAffectClasspath(_ path: String) -> Bool {
        let name = URL(filePath: path).lastPathComponent
        return name == "build.gradle"
            || name == "build.gradle.kts"
            || name == "settings.gradle"
            || name == "settings.gradle.kts"
            || name == "pom.xml"
            || name == "gradle.properties"
            || name == "gradlew"
            || name == "mvnw"
    }
}

private actor JavaSymbolWorkspaceWorker {
    struct Summary: Sendable {
        let fileCount: Int
        let sourceRoots: [URL]
        let sourceFiles: [URL]
    }

    private let fileManager = FileManager.default

    func summary(projectURL: URL) -> Summary {
        let urls = supportedJavaFileURLs(projectURL: projectURL)
        return Summary(
            fileCount: urls.count,
            sourceRoots: sourceRoots(projectURL: projectURL, fileURLs: urls),
            sourceFiles: urls
        )
    }

    private func supportedJavaFileURLs(projectURL: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: projectURL.standardizedFileURL,
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
                  fileURL.pathExtension.lowercased() == "java",
                  !gitIgnoreMatcher.isIgnored(fileURL, isDirectory: false) else {
                continue
            }
            urls.append(fileURL.standardizedFileURL)
        }

        return urls
    }

    private func sourceRoots(projectURL: URL, fileURLs: [URL]) -> [URL] {
        var roots: [URL] = [projectURL.standardizedFileURL]
        for fileURL in fileURLs {
            if let sourceRoot = conventionalSourceRoot(for: fileURL, projectURL: projectURL) {
                roots.append(sourceRoot)
            } else {
                roots.append(fileURL.deletingLastPathComponent().standardizedFileURL)
            }
        }

        var seen = Set<String>()
        return roots.compactMap { url in
            let standardized = url.standardizedFileURL
            let path = standardized.path(percentEncoded: false)
            return seen.insert(path).inserted ? standardized : nil
        }
    }

    private func conventionalSourceRoot(for fileURL: URL, projectURL: URL) -> URL? {
        let projectPath = projectURL.standardizedFileURL.path(percentEncoded: false)
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
        let prefix = projectPath.hasSuffix("/") ? projectPath : "\(projectPath)/"
        guard filePath.hasPrefix(prefix) else { return nil }

        let relativePath = String(filePath.dropFirst(prefix.count))
        let components = relativePath.split(separator: "/").map(String.init)
        guard let srcIndex = components.firstIndex(of: "src") else { return nil }
        for index in (srcIndex + 1)..<components.count where components[index] == "java" {
            let rootComponents = Array(components.prefix(index + 1))
            return rootComponents.reduce(projectURL.standardizedFileURL) { partialURL, component in
                partialURL.appending(path: component, directoryHint: .isDirectory)
            }
        }
        return nil
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
