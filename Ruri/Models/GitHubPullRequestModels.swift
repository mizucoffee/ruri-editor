//
//  GitHubPullRequestModels.swift
//  ruri
//

import Foundation

nonisolated struct GitHubPullRequestInfo: Equatable, Sendable {
    let number: Int
    let url: URL
    let isDraft: Bool
    let lifecycleState: GitHubPullRequestLifecycleState

    init(
        number: Int,
        url: URL,
        isDraft: Bool = false,
        lifecycleState: GitHubPullRequestLifecycleState
    ) {
        self.number = number
        self.url = url
        self.isDraft = isDraft
        self.lifecycleState = lifecycleState
    }

    var displayTitle: String {
        "#\(number)"
    }

    var displayStateDescription: String {
        isDraft ? "Draft, \(lifecycleState.displayName)" : lifecycleState.displayName
    }
}

nonisolated enum GitHubPullRequestLifecycleState: Equatable, Sendable {
    case open
    case closed
    case merged
    case unknown(String)

    init(rawValue: String) {
        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedValue.uppercased() {
        case "OPEN":
            self = .open
        case "CLOSED":
            self = .closed
        case "MERGED":
            self = .merged
        default:
            self = .unknown(normalizedValue)
        }
    }

    var displayName: String {
        switch self {
        case .open:
            "Open"
        case .closed:
            "Closed"
        case .merged:
            "Merged"
        case .unknown(let rawValue):
            rawValue.isEmpty ? "Unknown" : rawValue
        }
    }
}

nonisolated struct GitHubPullRequestDetails: Equatable, Sendable {
    let number: Int
    let url: URL
    let state: String
    let headBranchName: String
    let baseBranchName: String
    let headRepository: GitHubRepositoryIdentity
}

nonisolated struct GitHubPullRequestCreationLink: Equatable, Sendable {
    let baseBranch: String
    let headBranch: String
    let url: URL
}

nonisolated enum GitHubPullRequestStatus: Equatable, Sendable {
    case pullRequest(GitHubPullRequestInfo)
    case create(GitHubPullRequestCreationLink)
}
