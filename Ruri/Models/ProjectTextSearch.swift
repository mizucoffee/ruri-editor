//
//  ProjectTextSearch.swift
//  ruri
//

import Foundation

nonisolated struct TextRange: Equatable, Hashable, Sendable {
    let location: Int
    let length: Int

    nonisolated init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    nonisolated var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct ProjectTextSearchOptions: Equatable, Sendable {
    var query: String
    var directoryPath: String
    var fileMask: String
    var usesRegularExpression: Bool
    var isCaseSensitive: Bool

    nonisolated init(
        query: String = "",
        directoryPath: String = "",
        fileMask: String = "",
        usesRegularExpression: Bool = false,
        isCaseSensitive: Bool = false
    ) {
        self.query = query
        self.directoryPath = directoryPath
        self.fileMask = fileMask
        self.usesRegularExpression = usesRegularExpression
        self.isCaseSensitive = isCaseSensitive
    }

    nonisolated var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var trimmedDirectoryPath: String {
        directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var trimmedFileMask: String {
        fileMask.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ProjectTextSearchResult: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let url: URL
        let location: Int
        let length: Int
    }

    let url: URL
    let relativePath: String
    let fileName: String
    let lineNumber: Int
    let column: Int
    let lineText: String
    let matchRange: TextRange
    let lineMatchRange: TextRange

    nonisolated var id: ID {
        ID(url: url, location: matchRange.location, length: matchRange.length)
    }

    nonisolated var displayParentPath: String {
        let parentPath = (relativePath as NSString).deletingLastPathComponent
        return parentPath.isEmpty || parentPath == "." ? "." : parentPath
    }

    nonisolated var isInTestDirectory: Bool {
        SearchResultPathPolicy.isFileInTestDirectory(relativePath)
    }
}

struct ProjectTextSearchSummary: Equatable, Sendable {
    let searchedFileCount: Int
    let matchedFileCount: Int
    let skippedUnreadableFileCount: Int
    let didHitResultLimit: Bool
}

struct ProjectTextSearchResponse: Equatable, Sendable {
    let results: [ProjectTextSearchResult]
    let summary: ProjectTextSearchSummary

    nonisolated static let empty = ProjectTextSearchResponse(
        results: [],
        summary: ProjectTextSearchSummary(
            searchedFileCount: 0,
            matchedFileCount: 0,
            skippedUnreadableFileCount: 0,
            didHitResultLimit: false
        )
    )
}

enum ProjectTextSearchError: LocalizedError, Equatable, Sendable {
    case invalidRegularExpression(String)
    case invalidDirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidRegularExpression(let message):
            "正規表現が不正です: \(message)"
        case .invalidDirectory(let path):
            path.isEmpty
                ? "検索ディレクトリを開けません"
                : "検索ディレクトリを開けません: \(path)"
        }
    }
}
