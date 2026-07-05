//
//  GitHubPullRequestFileViewsModels.swift
//  ruri
//

import Foundation

nonisolated enum GitHubPullRequestFileViewedState: String, Equatable, Sendable {
    case viewed = "VIEWED"
    case unviewed = "UNVIEWED"
    case dismissed = "DISMISSED"
}

nonisolated struct GitHubPullRequestFileViews: Equatable, Sendable {
    let pullRequestNodeID: String
    let statesByPath: [String: GitHubPullRequestFileViewedState]
}

nonisolated enum GitHubPullRequestFileViewsResult: Equatable, Sendable {
    case available(GitHubPullRequestFileViews)
    case ignored(GitHubCLIOptionalIgnoredReason)
    case failed(String)
}

nonisolated enum GitHubPullRequestFileViewsError: LocalizedError, Equatable {
    case invalidPullRequestNumber(Int)
    case invalidPath(String)
    case invalidPullRequestNodeID(String)
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidPullRequestNumber(let number):
            "Invalid GitHub pull request number: \(number)."
        case .invalidPath(let path):
            "Invalid pull request file path: \(path)."
        case .invalidPullRequestNodeID(let nodeID):
            "Invalid GitHub pull request node ID: \(nodeID)."
        case .commandFailed(let message):
            message.isEmpty ? "GitHub pull request file views update failed." : message
        case .invalidResponse:
            "GitHub returned an invalid pull request file views response."
        }
    }
}
