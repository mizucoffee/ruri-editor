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
    let mergeableState: GitHubPullRequestMergeableState

    init(
        number: Int,
        url: URL,
        isDraft: Bool = false,
        lifecycleState: GitHubPullRequestLifecycleState,
        mergeableState: GitHubPullRequestMergeableState = .unknown
    ) {
        self.number = number
        self.url = url
        self.isDraft = isDraft
        self.lifecycleState = lifecycleState
        self.mergeableState = mergeableState
    }

    var displayTitle: String {
        "#\(number)"
    }

    var displayStateDescription: String {
        let baseDescription = isDraft ? "Draft, \(lifecycleState.displayName)" : lifecycleState.displayName
        guard showsConflicts else { return baseDescription }

        return "\(baseDescription), Conflicts"
    }

    /// コンフリクトの強調は open の PR に限る(closed/merged では意味を持たないため)。
    var showsConflicts: Bool {
        lifecycleState == .open && mergeableState == .conflicting
    }
}

nonisolated enum GitHubPullRequestMergeableState: Equatable, Sendable {
    case mergeable
    case conflicting
    case unknown

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "MERGEABLE":
            self = .mergeable
        case "CONFLICTING":
            self = .conflicting
        default:
            self = .unknown
        }
    }

    var isDeterminate: Bool {
        self != .unknown
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

    /// GitHub は mergeable を遅延計算するため push 直後は UNKNOWN が返る。
    /// 新ステータスが UNKNOWN のとき、同一 PR 番号の前回確定値を引き継いで表示の後退を防ぐ。
    func preservingDeterminateMergeableState(
        from previous: GitHubPullRequestStatus?
    ) -> GitHubPullRequestStatus {
        guard case .pullRequest(let newInfo) = self,
              newInfo.mergeableState == .unknown,
              case .pullRequest(let previousInfo)? = previous,
              previousInfo.number == newInfo.number,
              previousInfo.mergeableState.isDeterminate else {
            return self
        }

        return .pullRequest(GitHubPullRequestInfo(
            number: newInfo.number,
            url: newInfo.url,
            isDraft: newInfo.isDraft,
            lifecycleState: newInfo.lifecycleState,
            mergeableState: previousInfo.mergeableState
        ))
    }
}
