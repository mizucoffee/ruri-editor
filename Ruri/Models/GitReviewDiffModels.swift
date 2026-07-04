//
//  GitReviewDiffModels.swift
//  ruri
//

import Foundation

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
