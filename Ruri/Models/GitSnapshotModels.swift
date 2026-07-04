//
//  GitSnapshotModels.swift
//  ruri
//

import Foundation

nonisolated enum GitRepositoryStatus: Equatable, Sendable {
    case inactive
    case checking
    case notRepository(URL)
    case repository(GitRepositorySnapshot)

    var snapshot: GitRepositorySnapshot? {
        guard case .repository(let snapshot) = self else { return nil }
        return snapshot
    }
}

nonisolated enum GitFileDisplayStatus: String, Equatable, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case conflicted = "U"
    case untracked = "!"

    var description: String {
        switch self {
        case .modified:
            "Modified"
        case .added:
            "Added"
        case .deleted:
            "Deleted"
        case .renamed:
            "Renamed"
        case .copied:
            "Copied"
        case .conflicted:
            "Conflicted"
        case .untracked:
            "Untracked"
        }
    }
}

nonisolated struct GitFileChange: Equatable, Sendable {
    let url: URL
    let relativePath: String
    let originalURL: URL?
    let originalRelativePath: String?
    let indexStatus: Character?
    let worktreeStatus: Character?
    let isUntracked: Bool
    let isUnmerged: Bool

    init(
        url: URL,
        relativePath: String,
        originalURL: URL? = nil,
        originalRelativePath: String? = nil,
        indexStatus: Character? = nil,
        worktreeStatus: Character? = nil,
        isUntracked: Bool = false,
        isUnmerged: Bool = false
    ) {
        self.url = url.standardizedFileURL
        self.relativePath = relativePath
        self.originalURL = originalURL?.standardizedFileURL
        self.originalRelativePath = originalRelativePath
        self.indexStatus = indexStatus
        self.worktreeStatus = worktreeStatus
        self.isUntracked = isUntracked
        self.isUnmerged = isUnmerged
    }

    var displayStatus: GitFileDisplayStatus {
        if isUnmerged || indexStatus == "U" || worktreeStatus == "U" {
            return .conflicted
        }

        if isUntracked {
            return .untracked
        }

        let statuses = [indexStatus, worktreeStatus].compactMap { $0 }
        if statuses.contains("R") {
            return .renamed
        }
        if statuses.contains("C") {
            return .copied
        }
        if statuses.contains("A") {
            return .added
        }
        if statuses.contains("D") {
            return .deleted
        }

        return .modified
    }

    var isDeleted: Bool {
        displayStatus == .deleted
    }
}

nonisolated struct GitRepositorySnapshot: Equatable, Sendable {
    let repositoryRootURL: URL
    let worktreeRootURL: URL
    let openedRootURL: URL
    let gitDirectoryURL: URL
    let gitCommonDirectoryURL: URL
    let worktreeKind: GitWorktreeKind
    let worktreeRootURLs: [URL]
    let worktrees: [GitWorktreeInfo]
    let isRuriStyleWorktree: Bool
    let localBranches: [GitLocalBranchInfo]
    let branch: GitBranchState
    let changesByURL: [URL: GitFileChange]
    let diffsByURL: [URL: SourceFileDiff]

    init(
        repositoryRootURL: URL,
        worktreeRootURL: URL,
        openedRootURL: URL,
        gitDirectoryURL: URL,
        gitCommonDirectoryURL: URL,
        worktreeKind: GitWorktreeKind,
        worktreeRootURLs: [URL],
        worktrees: [GitWorktreeInfo] = [],
        isRuriStyleWorktree: Bool = false,
        localBranches: [GitLocalBranchInfo] = [],
        branch: GitBranchState,
        changesByURL: [URL: GitFileChange],
        diffsByURL: [URL: SourceFileDiff]
    ) {
        self.repositoryRootURL = repositoryRootURL.standardizedFileURL
        self.worktreeRootURL = worktreeRootURL.standardizedFileURL
        self.openedRootURL = openedRootURL.standardizedFileURL
        self.gitDirectoryURL = gitDirectoryURL.standardizedFileURL
        self.gitCommonDirectoryURL = gitCommonDirectoryURL.standardizedFileURL
        self.worktreeKind = worktreeKind
        self.worktreeRootURLs = worktreeRootURLs.map(\.standardizedFileURL)
        self.worktrees = worktrees.map { worktree in
            GitWorktreeInfo(
                rootURL: worktree.rootURL,
                branch: worktree.branch,
                headRevision: worktree.headRevision,
                kind: worktree.kind
            )
        }
        self.isRuriStyleWorktree = isRuriStyleWorktree
        self.localBranches = localBranches.map { branch in
            GitLocalBranchInfo(
                name: branch.name,
                checkedOutWorktreeURL: branch.checkedOutWorktreeURL
            )
        }
        self.branch = branch
        self.changesByURL = changesByURL
        self.diffsByURL = diffsByURL
    }

    var hasOtherWorktrees: Bool {
        worktreeRootURLs.contains { url in
            !FileURLRewriter.urlsMatch(url, worktreeRootURL)
        }
    }

    func change(for url: URL) -> GitFileChange? {
        let path = FileURLRewriter.normalizedPath(url)
        return changesByURL.first { FileURLRewriter.normalizedPath($0.key) == path }?.value
    }

    func diff(for url: URL) -> SourceFileDiff? {
        let path = FileURLRewriter.normalizedPath(url)
        return diffsByURL.first { FileURLRewriter.normalizedPath($0.key) == path }?.value
    }

    func updating(fileSnapshot: GitFileSnapshot) -> GitRepositorySnapshot {
        let filePath = FileURLRewriter.normalizedPath(fileSnapshot.url)
        var changesByURL = changesByURL.filter { url, _ in
            FileURLRewriter.normalizedPath(url) != filePath
        }
        var diffsByURL = diffsByURL.filter { url, _ in
            FileURLRewriter.normalizedPath(url) != filePath
        }

        if let change = fileSnapshot.change {
            changesByURL[change.url] = change
        }

        if let diff = fileSnapshot.diff {
            diffsByURL[fileSnapshot.url] = diff
        }

        return GitRepositorySnapshot(
            repositoryRootURL: repositoryRootURL,
            worktreeRootURL: worktreeRootURL,
            openedRootURL: openedRootURL,
            gitDirectoryURL: gitDirectoryURL,
            gitCommonDirectoryURL: gitCommonDirectoryURL,
            worktreeKind: worktreeKind,
            worktreeRootURLs: worktreeRootURLs,
            worktrees: worktrees,
            isRuriStyleWorktree: isRuriStyleWorktree,
            localBranches: localBranches,
            branch: branch,
            changesByURL: changesByURL,
            diffsByURL: diffsByURL
        )
    }

    func hasChangedDescendant(of directoryURL: URL) -> Bool {
        let directoryPath = FileURLRewriter.normalizedPath(directoryURL)
        let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : "\(directoryPath)/"

        return changesByURL.keys.contains { url in
            let path = FileURLRewriter.normalizedPath(url)
            return path.hasPrefix(directoryPrefix)
        }
    }

    func deletedChanges(in directoryURL: URL, excluding existingURLs: Set<URL>) -> [GitFileChange] {
        let existingPaths = Set(existingURLs.map(FileURLRewriter.normalizedPath))
        let directoryPath = FileURLRewriter.normalizedPath(directoryURL)

        return changesByURL.values
            .filter { change in
                guard change.isDeleted,
                      !existingPaths.contains(FileURLRewriter.normalizedPath(change.url)) else {
                    return false
                }

                return FileURLRewriter.normalizedPath(change.url.deletingLastPathComponent()) == directoryPath
            }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}

nonisolated struct GitFileSnapshot: Equatable, Sendable {
    let url: URL
    let change: GitFileChange?
    let diff: SourceFileDiff?

    init(
        url: URL,
        change: GitFileChange?,
        diff: SourceFileDiff?
    ) {
        self.url = url.standardizedFileURL
        self.change = change
        self.diff = diff
    }
}

nonisolated struct SourceFileDiff: Equatable, Sendable {
    let oldRelativePath: String?
    let newRelativePath: String?
    let hunks: [SourceDiffHunk]

    var displayRelativePath: String {
        newRelativePath ?? oldRelativePath ?? ""
    }

    var editorDecorations: [EditorDiffDecoration] {
        EditorDiffDecoration.decorations(for: self)
    }

    var additionCount: Int {
        hunks.reduce(0) { count, hunk in
            count + hunk.lines.filter { $0.kind == .addition }.count
        }
    }

    var deletionCount: Int {
        hunks.reduce(0) { count, hunk in
            count + hunk.lines.filter { $0.kind == .deletion }.count
        }
    }
}

nonisolated struct SourceDiffHunk: Equatable, Sendable {
    let oldStart: Int
    let oldLineCount: Int
    let newStart: Int
    let newLineCount: Int
    let lines: [SourceDiffLine]
}

nonisolated struct SourceDiffLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case context
        case addition
        case deletion
    }

    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let content: String
}

nonisolated struct EditorDiffDecoration: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case added
        case modified
        case deleted
    }

    let lineNumber: Int
    let kind: Kind

    static func decorations(for diff: SourceFileDiff) -> [EditorDiffDecoration] {
        var decorations: [EditorDiffDecoration] = []

        for hunk in diff.hunks {
            let addedLineNumbers = hunk.lines.compactMap { line in
                line.kind == .addition ? line.newLineNumber : nil
            }
            let deletedLineNumbers = hunk.lines.compactMap { line in
                line.kind == .deletion ? line.oldLineNumber : nil
            }

            if !addedLineNumbers.isEmpty, !deletedLineNumbers.isEmpty {
                let modifiedCount = min(addedLineNumbers.count, deletedLineNumbers.count)
                for lineNumber in addedLineNumbers.prefix(modifiedCount) {
                    decorations.append(EditorDiffDecoration(lineNumber: lineNumber, kind: .modified))
                }

                for lineNumber in addedLineNumbers.dropFirst(modifiedCount) {
                    decorations.append(EditorDiffDecoration(lineNumber: lineNumber, kind: .added))
                }

                if deletedLineNumbers.count > modifiedCount {
                    let anchorLine = max(1, hunk.newStart)
                    decorations.append(EditorDiffDecoration(lineNumber: anchorLine, kind: .deleted))
                }
                continue
            }

            if !addedLineNumbers.isEmpty {
                for lineNumber in addedLineNumbers {
                    decorations.append(EditorDiffDecoration(lineNumber: lineNumber, kind: .added))
                }
                continue
            }

            if !deletedLineNumbers.isEmpty {
                let anchorLine = max(1, hunk.newStart)
                decorations.append(EditorDiffDecoration(lineNumber: anchorLine, kind: .deleted))
            }
        }

        var seen = Set<EditorDiffDecoration>()
        return decorations.filter { seen.insert($0).inserted }
    }
}
