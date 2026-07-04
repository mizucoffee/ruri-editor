//
//  ProjectFileSearchIndex.swift
//  ruri
//

import Foundation

struct ProjectFileSearchEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let fileName: String
    let relativeParentPath: String
    let isInTestDirectory: Bool
    let matchTarget: FuzzyMatchTarget

    nonisolated init(url: URL, fileName: String, relativeParentPath: String) {
        self.url = url
        self.fileName = fileName
        self.relativeParentPath = relativeParentPath
        self.isInTestDirectory = SearchResultPathPolicy.isDirectoryInTestDirectory(relativeParentPath)
        self.matchTarget = FuzzyMatchTarget(relativeParentPath: relativeParentPath, fileName: fileName)
    }

    nonisolated var id: URL {
        url
    }

    nonisolated var displayParentPath: String {
        relativeParentPath.isEmpty ? "." : relativeParentPath
    }

}

struct ProjectFileSearchResult: Identifiable, Equatable, Sendable {
    let entry: ProjectFileSearchEntry
    let fileNameMatchOffsets: [Int]
    let parentPathMatchOffsets: [Int]

    nonisolated var id: URL {
        entry.url
    }
}

struct ProjectFileSearchIndex: Equatable, Sendable {
    nonisolated static let defaultResultLimit = 100

    let projectURL: URL
    let entries: [ProjectFileSearchEntry]

    nonisolated init(projectURL: URL, entries: [ProjectFileSearchEntry]) {
        self.projectURL = projectURL.standardizedFileURL
        self.entries = entries.sorted(by: Self.sortByDisplayOrder)
    }

    // 2フェーズ検索: 全エントリをスコアのみで走査してソートし、表示する上位limit件だけ
    // マッチ位置の復元（traceback付きDP）を行う
    nonisolated func search(
        matching query: String,
        limit: Int = Self.defaultResultLimit,
        shouldCancel: @Sendable () -> Bool = { false }
    ) -> [ProjectFileSearchResult] {
        let resultLimit = max(0, limit)
        guard resultLimit > 0, let fuzzyQuery = FuzzyQuery(rawQuery: query) else { return [] }

        var scorer = FuzzyFileScorer()
        var candidates: [(score: Int, entryIndex: Int)] = []

        for (entryIndex, entry) in entries.enumerated() {
            if entryIndex.isMultiple(of: 256), shouldCancel() {
                return []
            }

            guard let score = scorer.score(fuzzyQuery, in: entry.matchTarget) else { continue }
            candidates.append((score, entryIndex))
        }

        // 同スコアはtestディレクトリ外を先に、その中ではentriesの表示順（構築時ソート済み）を保つ
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            let lhsIsTest = entries[lhs.entryIndex].isInTestDirectory
            let rhsIsTest = entries[rhs.entryIndex].isInTestDirectory
            if lhsIsTest != rhsIsTest {
                return !lhsIsTest
            }

            return lhs.entryIndex < rhs.entryIndex
        }

        return candidates.prefix(resultLimit).compactMap { candidate in
            let entry = entries[candidate.entryIndex]
            guard let match = scorer.scoreWithPositions(fuzzyQuery, in: entry.matchTarget) else { return nil }
            return Self.makeResult(entry: entry, positions: match.positions)
        }
    }

    nonisolated private static func makeResult(
        entry: ProjectFileSearchEntry,
        positions: [Int]
    ) -> ProjectFileSearchResult {
        let fileNameStartIndex = entry.matchTarget.fileNameStartIndex
        var fileNameMatchOffsets: [Int] = []
        var parentPathMatchOffsets: [Int] = []

        for position in positions {
            if position >= fileNameStartIndex {
                fileNameMatchOffsets.append(position - fileNameStartIndex)
            } else if position < fileNameStartIndex - 1 {
                parentPathMatchOffsets.append(position)
            }
            // position == fileNameStartIndex - 1 は区切りの "/" で、表示文字列には存在しないため捨てる
        }

        return ProjectFileSearchResult(
            entry: entry,
            fileNameMatchOffsets: fileNameMatchOffsets,
            parentPathMatchOffsets: parentPathMatchOffsets
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
