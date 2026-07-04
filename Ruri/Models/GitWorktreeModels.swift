//
//  GitWorktreeModels.swift
//  ruri
//

import Foundation

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
