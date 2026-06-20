//
//  ProjectTextSearchService.swift
//  ruri
//

import Foundation

struct ProjectTextSearchService {
    nonisolated static let defaultResultLimit = 500

    nonisolated init() {}

    nonisolated func search(
        projectURL: URL,
        options: ProjectTextSearchOptions,
        resultLimit: Int = Self.defaultResultLimit
    ) async throws -> ProjectTextSearchResponse {
        try await Task.detached(priority: .userInitiated) {
            try Self.searchSnapshot(
                projectURL: projectURL.standardizedFileURL,
                options: options,
                resultLimit: resultLimit
            )
        }.value
    }

    nonisolated private static func searchSnapshot(
        projectURL: URL,
        options: ProjectTextSearchOptions,
        resultLimit: Int
    ) throws -> ProjectTextSearchResponse {
        let query = options.trimmedQuery
        guard !query.isEmpty else { return .empty }

        let searchRootURL = try searchRootURL(projectURL: projectURL, directoryPath: options.trimmedDirectoryPath)
        let fileMask = ProjectTextSearchFileMask(options.trimmedFileMask)
        let contentMatcher = try ProjectTextContentMatcher(
            query: query,
            usesRegularExpression: options.usesRegularExpression,
            isCaseSensitive: options.isCaseSensitive
        )
        let cappedResultLimit = max(0, resultLimit)

        guard cappedResultLimit > 0 else { return .empty }

        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: searchRootURL,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw ProjectTextSearchError.invalidDirectory(options.trimmedDirectoryPath)
        }

        var gitIgnoreMatcher = GitIgnoreMatcher(rootURL: projectURL)

        if searchRootURL != projectURL,
           gitIgnoreMatcher.isIgnored(searchRootURL, isDirectory: true) {
            return .empty
        }

        var candidateFiles: [(url: URL, relativePath: String, isInTestDirectory: Bool)] = []

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            let standardizedURL = fileURL.standardizedFileURL
            let values = try standardizedURL.resourceValues(forKeys: Set(keys))
            let isDirectory = values.isDirectory == true
            let name = standardizedURL.lastPathComponent

            if name == ".git" || name == ".ruri" {
                if isDirectory {
                    enumerator.skipDescendants()
                }

                continue
            }

            if isDirectory {
                if gitIgnoreMatcher.isIgnored(standardizedURL, isDirectory: true) {
                    enumerator.skipDescendants()
                }

                continue
            }

            guard values.isRegularFile == true else { continue }
            guard !gitIgnoreMatcher.isIgnored(standardizedURL, isDirectory: false) else { continue }

            let relativePath = relativePath(from: projectURL, to: standardizedURL)
            guard fileMask.matches(relativePath: relativePath, fileName: standardizedURL.lastPathComponent) else {
                continue
            }

            candidateFiles.append((
                url: standardizedURL,
                relativePath: relativePath,
                isInTestDirectory: SearchResultPathPolicy.isFileInTestDirectory(relativePath)
            ))
        }

        var results: [ProjectTextSearchResult] = []
        var matchedFileURLs = Set<URL>()
        var searchedFileCount = 0
        var skippedUnreadableFileCount = 0
        var didHitResultLimit = false

        for candidateFile in candidateFiles.sorted(by: {
            if $0.isInTestDirectory != $1.isInTestDirectory {
                return !$0.isInTestDirectory && $1.isInTestDirectory
            }

            return $0.relativePath < $1.relativePath
        }) {
            try Task.checkCancellation()
            searchedFileCount += 1

            guard let text = readableUTF8String(at: candidateFile.url) else {
                skippedUnreadableFileCount += 1
                continue
            }

            let remainingResultCount = cappedResultLimit - results.count
            let matches = contentMatcher.matches(in: text, limit: remainingResultCount)
            guard !matches.isEmpty else { continue }

            matchedFileURLs.insert(candidateFile.url)
            results.append(
                contentsOf: matches.map { match in
                    result(
                        for: match,
                        in: text,
                        fileURL: candidateFile.url,
                        relativePath: candidateFile.relativePath
                    )
                }
            )

            if results.count >= cappedResultLimit {
                didHitResultLimit = true
                break
            }
        }

        return ProjectTextSearchResponse(
            results: results,
            summary: ProjectTextSearchSummary(
                searchedFileCount: searchedFileCount,
                matchedFileCount: matchedFileURLs.count,
                skippedUnreadableFileCount: skippedUnreadableFileCount,
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

    nonisolated private static func readableUTF8String(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func result(
        for match: TextRange,
        in text: String,
        fileURL: URL,
        relativePath: String
    ) -> ProjectTextSearchResult {
        let string = text as NSString
        let textLength = string.length
        let matchLocation = min(match.location, textLength)
        let lineRange = string.lineRange(for: NSRange(location: matchLocation, length: 0))
        let rawLineText = string.substring(with: lineRange)
        let lineText = rawLineText.removingTrailingLineSeparators()
        let lineTextLength = (lineText as NSString).length
        let lineMatchLocation = min(max(0, matchLocation - lineRange.location), lineTextLength)
        let lineMatchLength = min(match.length, max(0, lineTextLength - lineMatchLocation))

        return ProjectTextSearchResult(
            url: fileURL,
            relativePath: relativePath,
            fileName: fileURL.lastPathComponent,
            lineNumber: lineNumber(at: matchLocation, in: string),
            column: columnNumber(in: text, lineStartLocation: lineRange.location, matchLocation: matchLocation),
            lineText: lineText,
            matchRange: match,
            lineMatchRange: TextRange(location: lineMatchLocation, length: lineMatchLength)
        )
    }

    nonisolated private static func lineNumber(at location: Int, in string: NSString) -> Int {
        guard location > 0,
              string.length > 0 else {
            return 1
        }

        let cappedLocation = min(location, string.length)
        var lineNumber = 1
        var searchRange = NSRange(location: 0, length: cappedLocation)

        while searchRange.length > 0 {
            let range = string.range(of: "\n", options: [], range: searchRange)
            guard range.location != NSNotFound else { break }

            lineNumber += 1
            let nextLocation = NSMaxRange(range)
            searchRange = NSRange(
                location: nextLocation,
                length: cappedLocation - nextLocation
            )
        }

        return lineNumber
    }

    nonisolated private static func columnNumber(
        in text: String,
        lineStartLocation: Int,
        matchLocation: Int
    ) -> Int {
        let utf16Length = text.utf16.count
        let lineStartOffset = min(max(0, lineStartLocation), utf16Length)
        let matchOffset = min(max(lineStartOffset, matchLocation), utf16Length)
        let lineStartUTF16Index = text.utf16.index(text.utf16.startIndex, offsetBy: lineStartOffset)
        let matchUTF16Index = text.utf16.index(text.utf16.startIndex, offsetBy: matchOffset)

        guard let lineStartIndex = String.Index(lineStartUTF16Index, within: text),
              let matchIndex = String.Index(matchUTF16Index, within: text) else {
            return matchOffset - lineStartOffset + 1
        }

        return text[lineStartIndex..<matchIndex].count + 1
    }

    nonisolated private static func relativePath(from rootURL: URL, to targetURL: URL) -> String {
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

private struct ProjectTextContentMatcher {
    private let query: String
    private let isCaseSensitive: Bool
    private let regularExpression: NSRegularExpression?

    nonisolated init(
        query: String,
        usesRegularExpression: Bool,
        isCaseSensitive: Bool
    ) throws {
        self.query = query
        self.isCaseSensitive = isCaseSensitive

        if usesRegularExpression {
            do {
                regularExpression = try NSRegularExpression(
                    pattern: query,
                    options: isCaseSensitive ? [] : [.caseInsensitive]
                )
            } catch {
                throw ProjectTextSearchError.invalidRegularExpression(error.localizedDescription)
            }
        } else {
            regularExpression = nil
        }
    }

    nonisolated func matches(in text: String, limit: Int) -> [TextRange] {
        guard limit > 0 else { return [] }

        if let regularExpression {
            return regexMatches(in: text, limit: limit, regularExpression: regularExpression)
        }

        return literalMatches(in: text, limit: limit)
    }

    nonisolated private func regexMatches(
        in text: String,
        limit: Int,
        regularExpression: NSRegularExpression
    ) -> [TextRange] {
        let string = text as NSString
        let fullRange = NSRange(location: 0, length: string.length)
        let matches = regularExpression.matches(in: text, options: [], range: fullRange)

        return Array(
            matches
                .prefix(limit)
                .map { match in
                    TextRange(location: match.range.location, length: match.range.length)
                }
        )
    }

    nonisolated private func literalMatches(in text: String, limit: Int) -> [TextRange] {
        let string = text as NSString
        let compareOptions: NSString.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
        var matches: [TextRange] = []
        var searchRange = NSRange(location: 0, length: string.length)

        while searchRange.length > 0 && matches.count < limit {
            let range = string.range(of: query, options: compareOptions, range: searchRange)
            guard range.location != NSNotFound else { break }

            matches.append(TextRange(location: range.location, length: range.length))

            let nextLocation = max(NSMaxRange(range), range.location + 1)
            guard nextLocation <= string.length else { break }

            searchRange = NSRange(
                location: nextLocation,
                length: string.length - nextLocation
            )
        }

        return matches
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

    nonisolated func matches(relativePath: String, fileName: String) -> Bool {
        let isIncluded = includePatterns.isEmpty || includePatterns.contains { pattern in
            Self.matches(pattern: pattern, relativePath: relativePath, fileName: fileName)
        }
        guard isIncluded else { return false }

        return !excludePatterns.contains { pattern in
            Self.matches(pattern: pattern, relativePath: relativePath, fileName: fileName)
        }
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

    nonisolated private static func matches(pattern: String, relativePath: String, fileName: String) -> Bool {
        var normalizedPattern = pattern
        while normalizedPattern.hasPrefix("/") {
            normalizedPattern.removeFirst()
        }

        guard !normalizedPattern.isEmpty else { return true }

        if normalizedPattern.contains("/") {
            return GlobMatcher.matchPath(
                normalizedPattern.split(separator: "/").map(String.init),
                relativePath.split(separator: "/").map(String.init)
            )
        }

        return GlobMatcher.matchComponent(normalizedPattern, fileName)
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
