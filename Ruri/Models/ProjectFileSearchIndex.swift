//
//  ProjectFileSearchIndex.swift
//  ruri
//

import Foundation

struct ProjectFileSearchEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let fileName: String
    let normalizedFileName: String
    let relativeParentPath: String
    let normalizedRelativePath: String
    let isInTestDirectory: Bool

    nonisolated init(url: URL, fileName: String, relativeParentPath: String) {
        self.url = url
        self.fileName = fileName
        self.normalizedFileName = fileName.lowercased()
        self.relativeParentPath = relativeParentPath
        let relativePath = relativeParentPath.isEmpty ? fileName : "\(relativeParentPath)/\(fileName)"
        self.normalizedRelativePath = relativePath.lowercased()
        self.isInTestDirectory = SearchResultPathPolicy.isDirectoryInTestDirectory(relativeParentPath)
    }

    nonisolated var id: URL {
        url
    }

    nonisolated var displayParentPath: String {
        relativeParentPath.isEmpty ? "." : relativeParentPath
    }

}

struct ProjectFileSearchIndex: Equatable, Sendable {
    private enum MatchRank: Int, CaseIterable {
        case fileNamePrefix = 0
        case fileNameContains = 1
        case relativePathPrefix = 2
        case relativePathContains = 3
    }

    nonisolated static let defaultResultLimit = 100

    let projectURL: URL
    let entries: [ProjectFileSearchEntry]

    nonisolated init(projectURL: URL, entries: [ProjectFileSearchEntry]) {
        self.projectURL = projectURL.standardizedFileURL
        self.entries = entries.sorted(by: Self.sortByDisplayOrder)
    }

    nonisolated func search(
        matching query: String,
        limit: Int = Self.defaultResultLimit,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> [ProjectFileSearchEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resultLimit = max(0, limit)
        guard !normalizedQuery.isEmpty, resultLimit > 0 else { return [] }

        var buckets = MatchBuckets(limit: resultLimit)

        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 256), shouldCancel() {
                return []
            }

            guard let rank = Self.matchRank(for: entry, normalizedQuery: normalizedQuery) else {
                continue
            }

            buckets.append(entry, rank: rank)
        }

        return buckets.results()
    }

    nonisolated private static func matchRank(
        for entry: ProjectFileSearchEntry,
        normalizedQuery: String
    ) -> MatchRank? {
        if entry.normalizedFileName.hasPrefix(normalizedQuery) {
            return .fileNamePrefix
        }

        if entry.normalizedFileName.contains(normalizedQuery) {
            return .fileNameContains
        }

        if entry.normalizedRelativePath.hasPrefix(normalizedQuery) {
            return .relativePathPrefix
        }

        if entry.normalizedRelativePath.contains(normalizedQuery) {
            return .relativePathContains
        }

        return nil
    }

    nonisolated private static func sortByDisplayOrder(
        _ lhs: ProjectFileSearchEntry,
        _ rhs: ProjectFileSearchEntry
    ) -> Bool {
        let fileNameOrder = lhs.fileName.localizedStandardCompare(rhs.fileName)
        if fileNameOrder != .orderedSame {
            return fileNameOrder == .orderedAscending
        }

        let pathOrder = lhs.relativeParentPath.localizedStandardCompare(rhs.relativeParentPath)
        if pathOrder != .orderedSame {
            return pathOrder == .orderedAscending
        }

        return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
    }

    nonisolated private struct MatchBuckets {
        private let limit: Int
        private var nonTestEntriesByRank = Array(repeating: [ProjectFileSearchEntry](), count: MatchRank.allCases.count)
        private var testEntriesByRank = Array(repeating: [ProjectFileSearchEntry](), count: MatchRank.allCases.count)

        init(limit: Int) {
            self.limit = limit
        }

        mutating func append(_ entry: ProjectFileSearchEntry, rank: MatchRank) {
            let rankIndex = rank.rawValue

            if entry.isInTestDirectory {
                guard testEntriesByRank[rankIndex].count < limit else { return }
                testEntriesByRank[rankIndex].append(entry)
                return
            }

            guard nonTestEntriesByRank[rankIndex].count < limit else { return }
            nonTestEntriesByRank[rankIndex].append(entry)
        }

        func results() -> [ProjectFileSearchEntry] {
            var results: [ProjectFileSearchEntry] = []
            results.reserveCapacity(limit)

            for rank in MatchRank.allCases {
                appendResults(from: nonTestEntriesByRank[rank.rawValue], to: &results)
                appendResults(from: testEntriesByRank[rank.rawValue], to: &results)
            }

            return results
        }

        private func appendResults(
            from bucket: [ProjectFileSearchEntry],
            to results: inout [ProjectFileSearchEntry]
        ) {
            guard results.count < limit else { return }

            let remainingCapacity = limit - results.count
            results.append(contentsOf: bucket.prefix(remainingCapacity))
        }
    }
}
