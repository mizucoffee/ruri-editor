//
//  GitBranchModels.swift
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
