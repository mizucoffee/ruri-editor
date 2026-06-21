//
//  ProjectTextSearchService.swift
//  ruri
//

import Foundation

struct ProjectTextSearchService {
    nonisolated static let defaultResultLimit = 500

    private let executableURL: URL?

    nonisolated init(
        executableURL: URL? = RipgrepExecutableResolver().bundledExecutableURL()
    ) {
        self.executableURL = executableURL
    }

    nonisolated func search(
        projectURL: URL,
        options: ProjectTextSearchOptions,
        resultLimit: Int = Self.defaultResultLimit
    ) async throws -> ProjectTextSearchResponse {
        guard let executableURL else {
            throw ProjectTextSearchError.searchExecutableNotFound
        }

        let worker = Task.detached(priority: .userInitiated) {
            try Self.searchSnapshot(
                executableURL: executableURL,
                projectURL: projectURL.standardizedFileURL,
                options: options,
                resultLimit: resultLimit
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func searchSnapshot(
        executableURL: URL,
        projectURL: URL,
        options: ProjectTextSearchOptions,
        resultLimit: Int
    ) throws -> ProjectTextSearchResponse {
        let query = options.trimmedQuery
        guard !query.isEmpty else { return .empty }

        let cappedResultLimit = max(0, resultLimit)
        guard cappedResultLimit > 0 else { return .empty }

        let searchRootURL = try searchRootURL(projectURL: projectURL, directoryPath: options.trimmedDirectoryPath)
        let searchPath = relativeSearchPath(from: projectURL, to: searchRootURL)
        let arguments = ripgrepArguments(
            query: query,
            options: options,
            resultLimit: cappedResultLimit,
            searchPath: searchPath
        )
        let commandResult = try RipgrepCommandRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: projectURL,
            resultLimit: cappedResultLimit
        )

        return try response(
            from: commandResult,
            projectURL: projectURL,
            resultLimit: cappedResultLimit,
            directoryPath: options.trimmedDirectoryPath
        )
    }

    nonisolated private static func ripgrepArguments(
        query: String,
        options: ProjectTextSearchOptions,
        resultLimit: Int,
        searchPath: String
    ) -> [String] {
        var arguments = [
            "--json",
            "--line-number",
            "--column",
            "--with-filename",
            "--hidden",
            "--no-heading",
            "--max-count",
            "\(resultLimit)",
            "--glob",
            "!.git/**",
            "--glob",
            "!.ruri/**"
        ]

        if !options.usesRegularExpression {
            arguments.append("--fixed-strings")
        }

        if !options.isCaseSensitive {
            arguments.append("--ignore-case")
        }

        for glob in ProjectTextSearchFileMask(options.trimmedFileMask).ripgrepGlobs {
            arguments.append("--glob")
            arguments.append(glob)
        }

        arguments.append("--")
        arguments.append(query)
        arguments.append(searchPath)

        return arguments
    }

    nonisolated private static func response(
        from commandResult: RipgrepCommandResult,
        projectURL: URL,
        resultLimit: Int,
        directoryPath: String
    ) throws -> ProjectTextSearchResponse {
        guard commandResult.didHitResultLimit ||
            commandResult.terminationStatus == 0 ||
            commandResult.terminationStatus == 1 else {
            let message = commandResult.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("regex parse error") ||
                message.localizedCaseInsensitiveContains("error parsing regex") {
                throw ProjectTextSearchError.invalidRegularExpression(message)
            }

            throw ProjectTextSearchError.searchFailed(message)
        }

        let parser = RipgrepJSONOutputParser(projectURL: projectURL)
        let parsedResponse = try parser.parse(commandResult.stdout)
        var parsedResults = parsedResponse.results

        parsedResults.sort {
            if $0.isInTestDirectory != $1.isInTestDirectory {
                return !$0.isInTestDirectory && $1.isInTestDirectory
            }

            if $0.relativePath != $1.relativePath {
                return $0.relativePath < $1.relativePath
            }

            if $0.lineNumber != $1.lineNumber {
                return $0.lineNumber < $1.lineNumber
            }

            return $0.column < $1.column
        }

        let limitedResults = Array(parsedResults.prefix(resultLimit))
        let didHitResultLimit = commandResult.didHitResultLimit ||
            parsedResponse.summary.didHitResultLimit ||
            parsedResults.count >= resultLimit

        return ProjectTextSearchResponse(
            results: limitedResults,
            summary: ProjectTextSearchSummary(
                searchedFileCount: parsedResponse.summary.searchedFileCount,
                matchedFileCount: Set(limitedResults.map(\.url)).count,
                skippedUnreadableFileCount: 0,
                didHitResultLimit: didHitResultLimit
            )
        )
    }

    nonisolated private static func searchRootURL(projectURL: URL, directoryPath: String) throws -> URL {
        let candidateURL: URL
        if directoryPath.isEmpty {
            candidateURL = projectURL
        } else if directoryPath.hasPrefix("/") {
            candidateURL = URL(filePath: directoryPath)
        } else {
            candidateURL = projectURL.appending(path: directoryPath, directoryHint: .isDirectory)
        }

        let standardizedURL = candidateURL.standardizedFileURL
        guard isDescendantOrSame(standardizedURL, of: projectURL) else {
            throw ProjectTextSearchError.invalidDirectory(directoryPath)
        }

        do {
            let values = try standardizedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                throw ProjectTextSearchError.invalidDirectory(directoryPath)
            }
        } catch let error as ProjectTextSearchError {
            throw error
        } catch {
            throw ProjectTextSearchError.invalidDirectory(directoryPath)
        }

        return standardizedURL
    }

    nonisolated private static func relativeSearchPath(from projectURL: URL, to searchRootURL: URL) -> String {
        let relativePath = relativePath(from: projectURL, to: searchRootURL)
        return relativePath.isEmpty ? "." : relativePath
    }

    nonisolated static func relativePath(from rootURL: URL, to targetURL: URL) -> String {
        let rootPath = normalizedDirectoryPath(rootURL)
        let targetPath = targetURL.standardizedFileURL.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        guard targetPath.hasPrefix(rootPrefix) else {
            return targetURL.lastPathComponent
        }

        return String(targetPath.dropFirst(rootPrefix.count))
    }

    nonisolated private static func isDescendantOrSame(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let rootPath = normalizedDirectoryPath(rootURL)
        let candidatePath = normalizedDirectoryPath(candidateURL)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"

        return candidatePath == rootPath || candidatePath.hasPrefix(rootPrefix)
    }

    nonisolated private static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)

        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }
}

nonisolated struct RipgrepExecutableResolver {
    func bundledExecutableURL(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.url(forResource: "rg", withExtension: nil, subdirectory: "Tools"),
            bundle.url(forResource: "rg", withExtension: nil, subdirectory: "Resources/Tools"),
            bundle.url(forResource: "rg", withExtension: nil)
        ]

        return candidates.compactMap(\.self).first { url in
            FileManager.default.isExecutableFile(atPath: url.path(percentEncoded: false))
        }
    }
}

private struct ProjectTextSearchFileMask {
    private let includePatterns: [String]
    private let excludePatterns: [String]

    nonisolated init(_ fileMask: String) {
        var includes: [String] = []
        var excludes: [String] = []

        for token in Self.tokens(in: fileMask) {
            if token.hasPrefix("!") {
                let pattern = String(token.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                if !pattern.isEmpty {
                    excludes.append(pattern)
                }
            } else {
                includes.append(token)
            }
        }

        includePatterns = includes
        excludePatterns = excludes
    }

    nonisolated var ripgrepGlobs: [String] {
        includePatterns + excludePatterns.map { "!\($0)" }
    }

    nonisolated private static func tokens(in fileMask: String) -> [String] {
        fileMask
            .split { character in
                character == "," ||
                    character == ";" ||
                    character == " " ||
                    character == "\t" ||
                    character == "\n" ||
                    character == "\r"
            }
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

nonisolated private struct RipgrepCommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
    let didHitResultLimit: Bool

    nonisolated var stderrString: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

nonisolated private enum RipgrepCommandRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        resultLimit: Int
    ) throws -> RipgrepCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdout = RipgrepLimitedOutput(resultLimit: resultLimit)
        let stderr = RipgrepLockedData()
        let terminationSemaphore = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "LANG": "C"
        ]) { _, newValue in newValue }
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                let shouldTerminate = stdout.append(data)
                if shouldTerminate, process.isRunning {
                    process.terminate()
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderr.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
            throw ProjectTextSearchError.searchExecutableNotFound
        }

        while terminationSemaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if Task.isCancelled {
                process.terminate()
                process.waitUntilExit()
                cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
                throw CancellationError()
            }
        }

        cleanup(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)
        appendRemainingData(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, stdout: stdout, stderr: stderr)

        return RipgrepCommandResult(
            stdout: stdout.data(),
            stderr: stderr.data(),
            terminationStatus: process.terminationStatus,
            didHitResultLimit: stdout.didHitResultLimit()
        )
    }

    private static func cleanup(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
    }

    private static func appendRemainingData(
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        stdout: RipgrepLimitedOutput,
        stderr: RipgrepLockedData
    ) {
        let remainingStdout = stdoutPipe.fileHandleForReading.availableData
        if !remainingStdout.isEmpty {
            _ = stdout.append(remainingStdout)
        }
        let remainingStderr = stderrPipe.fileHandleForReading.availableData
        if !remainingStderr.isEmpty {
            stderr.append(remainingStderr)
        }
    }
}

nonisolated private final class RipgrepLockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData = Data()

    func append(_ data: Data) {
        lock.lock()
        storedData.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let data = storedData
        lock.unlock()
        return data
    }
}

nonisolated private final class RipgrepLimitedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private let resultLimit: Int
    private var storedData = Data()
    private var pendingText = ""
    private var matchCount = 0
    private var hitLimit = false

    init(resultLimit: Int) {
        self.resultLimit = max(0, resultLimit)
    }

    func append(_ data: Data) -> Bool {
        lock.lock()
        storedData.append(data)
        let shouldTerminate = updateMatchCount(with: data)
        lock.unlock()

        return shouldTerminate
    }

    func data() -> Data {
        lock.lock()
        let data = storedData
        lock.unlock()
        return data
    }

    func didHitResultLimit() -> Bool {
        lock.lock()
        let didHit = hitLimit
        lock.unlock()
        return didHit
    }

    private func updateMatchCount(with data: Data) -> Bool {
        guard resultLimit > 0,
              !hitLimit,
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        pendingText += text
        let lines = pendingText.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return false }

        pendingText = String(lines.last ?? "")
        for line in lines.dropLast() where line.contains(#""type":"match""#) {
            matchCount += line.components(separatedBy: #""start":"#).count - 1
            if matchCount >= resultLimit {
                hitLimit = true
                return true
            }
        }

        return false
    }
}

nonisolated private struct RipgrepJSONOutputParser {
    private let projectURL: URL
    private let decoder = JSONDecoder()
    private let fileTextCache = RipgrepFileTextCache()

    init(projectURL: URL) {
        self.projectURL = projectURL
    }

    func parse(_ data: Data) throws -> ProjectTextSearchResponse {
        var results: [ProjectTextSearchResult] = []
        var searchedFileCount = 0
        var didHitResultLimit = false

        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8) else { continue }
            let event = try decoder.decode(RipgrepEvent.self, from: lineData)

            switch event.type {
            case "match":
                guard let result = result(from: event) else { continue }
                results.append(contentsOf: result)
            case "end":
                searchedFileCount += 1
            case "summary":
                if let matchedLines = event.data.stats?.matchedLines,
                   matchedLines > 0,
                   results.isEmpty {
                    didHitResultLimit = false
                }
            default:
                continue
            }
        }

        return ProjectTextSearchResponse(
            results: results,
            summary: ProjectTextSearchSummary(
                searchedFileCount: searchedFileCount,
                matchedFileCount: Set(results.map(\.url)).count,
                skippedUnreadableFileCount: 0,
                didHitResultLimit: didHitResultLimit
            )
        )
    }

    private func result(from event: RipgrepEvent) -> [ProjectTextSearchResult]? {
        guard let pathText = event.data.path?.text,
              let lineText = event.data.lines?.text,
              let lineNumber = event.data.lineNumber,
              let absoluteOffset = event.data.absoluteOffset else {
            return nil
        }

        let relativePath = normalizedRelativePath(pathText)
        let url = projectURL.appending(path: relativePath)
        let normalizedLineText = lineText.removingTrailingLineSeparators()

        let fileText = fileTextCache.text(at: url)

        return event.data.submatches.map { submatch in
            let matchByteLocation = absoluteOffset + submatch.start
            let matchByteEnd = absoluteOffset + submatch.end
            let lineStart = utf16Offset(in: normalizedLineText, forUTF8ByteOffset: submatch.start)
            let lineEnd = utf16Offset(in: normalizedLineText, forUTF8ByteOffset: submatch.end)
            let matchStart = fileText.map {
                utf16Offset(in: $0, forUTF8ByteOffset: matchByteLocation)
            } ?? matchByteLocation
            let matchEnd = fileText.map {
                utf16Offset(in: $0, forUTF8ByteOffset: matchByteEnd)
            } ?? matchByteEnd

            return ProjectTextSearchResult(
                url: url,
                relativePath: relativePath,
                fileName: url.lastPathComponent,
                lineNumber: lineNumber,
                column: characterColumn(in: normalizedLineText, forUTF8ByteOffset: submatch.start),
                lineText: normalizedLineText,
                matchRange: TextRange(location: matchStart, length: max(0, matchEnd - matchStart)),
                lineMatchRange: TextRange(location: lineStart, length: max(0, lineEnd - lineStart))
            )
        }
    }

    private func normalizedRelativePath(_ path: String) -> String {
        if path == "." {
            return ""
        }

        let absolutePath = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        if path.hasPrefix("/") {
            return ProjectTextSearchService.relativePath(from: projectURL, to: URL(filePath: absolutePath))
        }

        var relativePath = path
        while relativePath.hasPrefix("./") {
            relativePath.removeFirst(2)
        }

        return relativePath
    }

    private func utf16Offset(in text: String, forUTF8ByteOffset byteOffset: Int) -> Int {
        let clampedOffset = min(max(0, byteOffset), text.utf8.count)
        let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: clampedOffset)

        guard let index = String.Index(utf8Index, within: text) else {
            return clampedOffset
        }

        guard let utf16Index = index.samePosition(in: text.utf16) else {
            return clampedOffset
        }

        return text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
    }

    private func characterColumn(in text: String, forUTF8ByteOffset byteOffset: Int) -> Int {
        let clampedOffset = min(max(0, byteOffset), text.utf8.count)
        let utf8Index = text.utf8.index(text.utf8.startIndex, offsetBy: clampedOffset)

        guard let index = String.Index(utf8Index, within: text) else {
            return clampedOffset + 1
        }

        return text.distance(from: text.startIndex, to: index) + 1
    }
}

nonisolated private final class RipgrepFileTextCache: @unchecked Sendable {
    private let lock = NSLock()
    private var textsByURL: [URL: String?] = [:]

    func text(at url: URL) -> String? {
        lock.lock()
        if let cached = textsByURL[url] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let text = try? String(contentsOf: url, encoding: .utf8)

        lock.lock()
        textsByURL[url] = text
        lock.unlock()

        return text
    }
}

nonisolated private struct RipgrepEvent: Decodable {
    let type: String
    let data: DataPayload

    struct DataPayload: Decodable {
        let path: TextPayload?
        let lines: TextPayload?
        let lineNumber: Int?
        let absoluteOffset: Int?
        let submatches: [Submatch]
        let stats: Stats?

        enum CodingKeys: String, CodingKey {
            case path
            case lines
            case lineNumber = "line_number"
            case absoluteOffset = "absolute_offset"
            case submatches
            case stats
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decodeIfPresent(TextPayload.self, forKey: .path)
            lines = try container.decodeIfPresent(TextPayload.self, forKey: .lines)
            lineNumber = try container.decodeIfPresent(Int.self, forKey: .lineNumber)
            absoluteOffset = try container.decodeIfPresent(Int.self, forKey: .absoluteOffset)
            submatches = try container.decodeIfPresent([Submatch].self, forKey: .submatches) ?? []
            stats = try container.decodeIfPresent(Stats.self, forKey: .stats)
        }
    }

    struct TextPayload: Decodable {
        let text: String?
    }

    struct Submatch: Decodable {
        let start: Int
        let end: Int
    }

    struct Stats: Decodable {
        let matchedLines: Int?

        enum CodingKeys: String, CodingKey {
            case matchedLines = "matched_lines"
        }
    }
}

private extension String {
    nonisolated func removingTrailingLineSeparators() -> String {
        var result = self

        while result.hasSuffix("\n") || result.hasSuffix("\r") {
            result.removeLast()
        }

        return result
    }
}
