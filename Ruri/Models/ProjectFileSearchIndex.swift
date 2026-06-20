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

    nonisolated init(url: URL, fileName: String, relativeParentPath: String) {
        self.url = url
        self.fileName = fileName
        self.normalizedFileName = fileName.lowercased()
        self.relativeParentPath = relativeParentPath
        let relativePath = relativeParentPath.isEmpty ? fileName : "\(relativeParentPath)/\(fileName)"
        self.normalizedRelativePath = relativePath.lowercased()
    }

    nonisolated var id: URL {
        url
    }

    nonisolated var displayParentPath: String {
        relativeParentPath.isEmpty ? "." : relativeParentPath
    }

    nonisolated var isInTestDirectory: Bool {
        SearchResultPathPolicy.isDirectoryInTestDirectory(relativeParentPath)
    }
}

struct ProjectFileSearchIndex: Equatable, Sendable {
    private enum MatchRank: Int {
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
        limit: Int = Self.defaultResultLimit
    ) -> [ProjectFileSearchEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        let matches = entries.compactMap { entry -> (entry: ProjectFileSearchEntry, rank: MatchRank)? in
            if entry.normalizedFileName.hasPrefix(normalizedQuery) {
                return (entry, .fileNamePrefix)
            }

            if entry.normalizedFileName.contains(normalizedQuery) {
                return (entry, .fileNameContains)
            }

            if entry.normalizedRelativePath.hasPrefix(normalizedQuery) {
                return (entry, .relativePathPrefix)
            }

            if entry.normalizedRelativePath.contains(normalizedQuery) {
                return (entry, .relativePathContains)
            }

            return nil
        }

        return Array(
            matches
                .sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank.rawValue < rhs.rank.rawValue
            }

            if lhs.entry.isInTestDirectory != rhs.entry.isInTestDirectory {
                return !lhs.entry.isInTestDirectory && rhs.entry.isInTestDirectory
            }

            return Self.sortByDisplayOrder(lhs.entry, rhs.entry)
        }
                .prefix(max(0, limit))
                .map(\.entry)
        )
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
}
