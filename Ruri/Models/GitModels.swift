//
//  GitModels.swift
//  ruri
//

import Foundation

nonisolated enum GitBranchState: Equatable, Sendable {
    case branch(String)
    case detached(String)
    case unborn(String)

    var displayName: String {
        switch self {
        case .branch(let name), .unborn(let name):
            name
        case .detached(let revision):
            revision.isEmpty ? "Detached" : revision
        }
    }

    var detail: String {
        switch self {
        case .branch(let name):
            "On branch \(name)"
        case .detached(let revision):
            revision.isEmpty ? "Detached HEAD" : "Detached at \(revision)"
        case .unborn(let name):
            "On unborn branch \(name)"
        }
    }
}

nonisolated enum GitWorktreeKind: Equatable, Sendable {
    case main
    case linked
}

nonisolated struct GitWorktreeInfo: Equatable, Sendable {
    let rootURL: URL
    let branch: GitBranchState?
    let headRevision: String?
    let kind: GitWorktreeKind

    init(
        rootURL: URL,
        branch: GitBranchState?,
        headRevision: String?,
        kind: GitWorktreeKind
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.branch = branch
        self.headRevision = headRevision
        self.kind = kind
    }

    var displayName: String {
        if let branch {
            return branch.displayName
        }

        if let headRevision,
           !headRevision.isEmpty {
            return String(headRevision.prefix(7))
        }

        return rootURL.lastPathComponent
    }
}

nonisolated struct GitLocalBranchInfo: Equatable, Identifiable, Sendable {
    let name: String
    let checkedOutWorktreeURL: URL?

    init(name: String, checkedOutWorktreeURL: URL?) {
        self.name = name
        self.checkedOutWorktreeURL = checkedOutWorktreeURL?.standardizedFileURL
    }

    var id: String {
        name
    }
}

nonisolated struct GitRemoteBranchInfo: Equatable, Identifiable, Sendable {
    let fullName: String
    let remoteName: String
    let branchName: String

    init?(fullName: String) {
        let fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullName.isEmpty,
              !fullName.hasSuffix("/HEAD"),
              let separatorIndex = fullName.firstIndex(of: "/") else {
            return nil
        }

        let remoteName = String(fullName[..<separatorIndex])
        let branchNameStartIndex = fullName.index(after: separatorIndex)
        let branchName = String(fullName[branchNameStartIndex...])
        guard !remoteName.isEmpty,
              !branchName.isEmpty else {
            return nil
        }

        self.fullName = fullName
        self.remoteName = remoteName
        self.branchName = branchName
    }

    var id: String {
        fullName
    }
}

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

nonisolated enum GitWorktreeCreationError: LocalizedError, Sendable {
    case gitUnavailable
    case notRepository(URL)
    case invalidBranchName(String)
    case branchAlreadyExists(String)
    case remoteBranchNotFound(String)
    case worktreePathAlreadyExists(URL)
    case worktreePathOutsideParent(URL)
    case timedOut
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git executable is not available."
        case .notRepository(let url):
            "\(url.path(percentEncoded: false)) is not in a Git repository."
        case .invalidBranchName(let branchName):
            "\(branchName) is not a valid branch name."
        case .branchAlreadyExists(let branchName):
            "Local branch \(branchName) already exists."
        case .remoteBranchNotFound(let branchName):
            "Remote branch \(branchName) was not found."
        case .worktreePathAlreadyExists(let url):
            "\(url.path(percentEncoded: false)) already exists."
        case .worktreePathOutsideParent(let url):
            "\(url.path(percentEncoded: false)) is not a valid worktree path."
        case .timedOut:
            "Git worktree creation timed out."
        case .gitCommandFailed(let message):
            message.isEmpty ? "Git worktree creation failed." : message
        }
    }
}

nonisolated enum GitWorktreeDeletionError: LocalizedError, Sendable {
    case gitUnavailable
    case notRepository(URL)
    case cannotDeleteMainWorktree(URL)
    case worktreeNotFound(URL)
    case timedOut
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git executable is not available."
        case .notRepository(let url):
            "\(url.path(percentEncoded: false)) is not in a Git repository."
        case .cannotDeleteMainWorktree(let url):
            "\(url.path(percentEncoded: false)) is the main worktree. Only linked worktrees can be deleted."
        case .worktreeNotFound(let url):
            "\(url.path(percentEncoded: false)) is not an opened worktree."
        case .timedOut:
            "Git worktree deletion timed out."
        case .gitCommandFailed(let message):
            message.isEmpty ? "Git worktree deletion failed." : message
        }
    }
}

nonisolated enum GitPullError: LocalizedError, Sendable {
    case gitUnavailable
    case notRepository(URL)
    case timedOut
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git executable is not available."
        case .notRepository(let url):
            "\(url.path(percentEncoded: false)) is not in a Git repository."
        case .timedOut:
            "Git pull timed out."
        case .gitCommandFailed(let message):
            message.isEmpty ? "Git pull failed." : message
        }
    }
}

nonisolated enum GitBranchSwitchError: LocalizedError, Sendable {
    case gitUnavailable
    case notRepository(URL)
    case notRuriStyleWorktree(URL)
    case invalidBranchName(String)
    case branchNotFound(String)
    case branchAlreadyCheckedOut(String, URL)
    case timedOut
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git executable is not available."
        case .notRepository(let url):
            "\(url.path(percentEncoded: false)) is not in a Git repository."
        case .notRuriStyleWorktree(let url):
            "\(url.path(percentEncoded: false)) is not a ruri-style worktree."
        case .invalidBranchName(let branchName):
            "\(branchName) is not a valid branch name."
        case .branchNotFound(let branchName):
            "Branch \(branchName) was not found."
        case .branchAlreadyCheckedOut(let branchName, let url):
            "Branch \(branchName) is already checked out at \(url.path(percentEncoded: false))."
        case .timedOut:
            "Git branch switch timed out."
        case .gitCommandFailed(let message):
            message.isEmpty ? "Git branch switch failed." : message
        }
    }
}

nonisolated enum GitReviewDiffError: LocalizedError, Sendable {
    case gitUnavailable
    case notRepository(URL)
    case invalidBaseBranch(String)
    case mergeBaseNotFound(String)
    case timedOut
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitUnavailable:
            "Git executable is not available."
        case .notRepository(let url):
            "\(url.path(percentEncoded: false)) is not in a Git repository."
        case .invalidBaseBranch(let branchName):
            "Base branch \(branchName) was not found."
        case .mergeBaseNotFound(let branchName):
            "Could not find a merge base with \(branchName)."
        case .timedOut:
            "Git review diff timed out."
        case .gitCommandFailed(let message):
            message.isEmpty ? "Git review diff failed." : message
        }
    }
}

nonisolated enum GitReviewDiffBase: Equatable, Sendable {
    case branch(String)
    case uncommitted

    var displayName: String {
        switch self {
        case .branch(let name):
            name
        case .uncommitted:
            "Uncommitted changes"
        }
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

nonisolated struct GitReviewDiffOptions: Equatable, Sendable {
    static let `default` = GitReviewDiffOptions()

    let hideWhitespace: Bool

    init(hideWhitespace: Bool = false) {
        self.hideWhitespace = hideWhitespace
    }
}

nonisolated struct GitReviewDiffSnapshot: Equatable, Sendable {
    let base: GitReviewDiffBase
    let targetBranch: GitBranchState
    let targetWorktreeRootURL: URL
    let baseRevision: String
    let files: [GitReviewFileDiff]

    init(
        base: GitReviewDiffBase,
        targetBranch: GitBranchState,
        targetWorktreeRootURL: URL,
        baseRevision: String,
        files: [GitReviewFileDiff]
    ) {
        self.base = base
        self.targetBranch = targetBranch
        self.targetWorktreeRootURL = targetWorktreeRootURL.standardizedFileURL
        self.baseRevision = baseRevision
        self.files = files
    }

    init(
        baseBranch: String,
        targetBranch: GitBranchState,
        targetWorktreeRootURL: URL,
        mergeBaseRevision: String,
        files: [GitReviewFileDiff]
    ) {
        self.init(
            base: .branch(baseBranch),
            targetBranch: targetBranch,
            targetWorktreeRootURL: targetWorktreeRootURL,
            baseRevision: mergeBaseRevision,
            files: files
        )
    }

    var baseDisplayName: String {
        base.displayName
    }

    var baseBranch: String {
        base.displayName
    }

    var mergeBaseRevision: String {
        baseRevision
    }

    var totalAdditions: Int {
        files.reduce(0) { $0 + $1.additions }
    }

    var totalDeletions: Int {
        files.reduce(0) { $0 + $1.deletions }
    }

    func applying(_ update: GitReviewDiffUpdate) -> GitReviewDiffSnapshot? {
        guard base == update.base,
              targetBranch == update.targetBranch,
              FileURLRewriter.urlsMatch(targetWorktreeRootURL, update.targetWorktreeRootURL),
              baseRevision == update.baseRevision else {
            return nil
        }

        var updatedFiles = files.filter { file in
            !update.replaces(file)
        }
        updatedFiles.append(contentsOf: update.files)
        updatedFiles.sort { lhs, rhs in
            lhs.displayRelativePath.localizedStandardCompare(rhs.displayRelativePath) == .orderedAscending
        }

        return GitReviewDiffSnapshot(
            base: base,
            targetBranch: targetBranch,
            targetWorktreeRootURL: targetWorktreeRootURL,
            baseRevision: baseRevision,
            files: updatedFiles
        )
    }
}

nonisolated struct GitReviewDiffUpdate: Equatable, Sendable {
    let base: GitReviewDiffBase
    let targetBranch: GitBranchState
    let targetWorktreeRootURL: URL
    let baseRevision: String
    let requestedRelativePaths: Set<String>
    let files: [GitReviewFileDiff]

    init(
        base: GitReviewDiffBase,
        targetBranch: GitBranchState,
        targetWorktreeRootURL: URL,
        baseRevision: String,
        requestedRelativePaths: Set<String>,
        files: [GitReviewFileDiff]
    ) {
        self.base = base
        self.targetBranch = targetBranch
        self.targetWorktreeRootURL = targetWorktreeRootURL.standardizedFileURL
        self.baseRevision = baseRevision
        self.requestedRelativePaths = Set(requestedRelativePaths.map(Self.normalizedRelativePath))
        self.files = files
    }

    func replaces(_ file: GitReviewFileDiff) -> Bool {
        relativePaths(for: file).contains { requestedRelativePaths.contains($0) }
    }

    private func relativePaths(for file: GitReviewFileDiff) -> [String] {
        [file.oldRelativePath, file.newRelativePath]
            .compactMap { $0.map(Self.normalizedRelativePath) }
    }

    private static func normalizedRelativePath(_ relativePath: String) -> String {
        relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

nonisolated struct GitReviewFileDiff: Identifiable, Equatable, Sendable {
    let oldRelativePath: String?
    let newRelativePath: String?
    let status: GitFileDisplayStatus
    let additions: Int
    let deletions: Int
    let isBinary: Bool
    let diff: SourceFileDiff

    init(
        oldRelativePath: String?,
        newRelativePath: String?,
        status: GitFileDisplayStatus,
        additions: Int,
        deletions: Int,
        isBinary: Bool = false,
        diff: SourceFileDiff
    ) {
        self.oldRelativePath = oldRelativePath
        self.newRelativePath = newRelativePath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
        self.diff = diff
    }

    init(
        diff: SourceFileDiff,
        status: GitFileDisplayStatus? = nil,
        isBinary: Bool = false
    ) {
        self.init(
            oldRelativePath: diff.oldRelativePath,
            newRelativePath: diff.newRelativePath,
            status: status ?? Self.status(for: diff),
            additions: diff.additionCount,
            deletions: diff.deletionCount,
            isBinary: isBinary,
            diff: diff
        )
    }

    var id: String {
        "\(oldRelativePath ?? "")\u{0}\(newRelativePath ?? "")"
    }

    var displayRelativePath: String {
        newRelativePath ?? oldRelativePath ?? ""
    }

    private static func status(for diff: SourceFileDiff) -> GitFileDisplayStatus {
        switch (diff.oldRelativePath, diff.newRelativePath) {
        case (nil, _):
            .added
        case (_, nil):
            .deleted
        case (let oldPath?, let newPath?) where oldPath != newPath:
            .renamed
        default:
            .modified
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
