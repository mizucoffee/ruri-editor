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
    /// 表示キャップ適用後の等幅カラム数。折り返し表示行数の推定に使うため、
    /// UI スレッドで都度計測せずパース時に前計算しておく。
    let displayColumnCount: Int

    init(kind: Kind, oldLineNumber: Int?, newLineNumber: Int?, content: String) {
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.content = content
        self.displayColumnCount = SourceDiffLineDisplay.columnCount(of: content)
    }
}

/// 差分行の表示上の長さの取り扱い。レイヤーバックの差分ペインは CA レイヤー
/// (Metal テクスチャ)上限を超えた部分の描画が破棄されるため、極端な長行は
/// 表示前に切り詰め、折り返し行数はカラム数から推定する。
nonisolated enum SourceDiffLineDisplay {
    /// 1行あたりの表示キャップ(UTF-16 単位)。非折り返し時のペイン幅
    /// (約7.2pt/字)がレイヤー上限 ~8,192pt を超えないよう抑える。
    static let maxRenderedLineUTF16Length = 1024
    static let truncationMarker = "…"
    /// 描画側の defaultTabInterval(スペース4個分)と一致させること。
    static let tabDisplayColumnWidth = 4

    /// キャップを適用した表示用文字列。Character 境界を守って切り詰める。
    static func cappedContent(_ content: String) -> String {
        let utf16 = content.utf16
        guard utf16.count > maxRenderedLineUTF16Length else { return content }

        var cut = utf16.index(utf16.startIndex, offsetBy: maxRenderedLineUTF16Length)
        var boundary = String.Index(cut, within: content)
        while boundary == nil, cut > utf16.startIndex {
            cut = utf16.index(before: cut)
            boundary = String.Index(cut, within: content)
        }
        guard let boundary else { return truncationMarker }
        return String(content[..<boundary]) + truncationMarker
    }

    /// キャップ適用後の等幅カラム数(タブ = 次の4カラム境界、東アジア全角 = 2)。
    /// 空行は表示上スペース1個になるため最低1を返す。
    static func columnCount(of content: String) -> Int {
        var columns = 0
        for scalar in cappedContent(content).unicodeScalars {
            if scalar == "\t" {
                columns += tabDisplayColumnWidth - columns % tabDisplayColumnWidth
            } else {
                columns += isWideScalar(scalar) ? 2 : 1
            }
        }
        return max(1, columns)
    }

    private static func isWideScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
             0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x1F300...0x1FAFF, 0x20000...0x3FFFD:
            true
        default:
            false
        }
    }
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
