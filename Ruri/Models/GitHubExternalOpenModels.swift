//
//  GitHubExternalOpenModels.swift
//  ruri
//

import Foundation

nonisolated struct GitHubRepositoryIdentity: Equatable, Hashable, Sendable {
    let owner: String
    let name: String

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    func matches(_ other: GitHubRepositoryIdentity) -> Bool {
        owner.caseInsensitiveCompare(other.owner) == .orderedSame
            && name.caseInsensitiveCompare(other.name) == .orderedSame
    }
}

nonisolated struct GitHubPullRequestExternalReference: Equatable, Sendable {
    let repository: GitHubRepositoryIdentity
    let number: Int
}

nonisolated enum GitHubExternalURLParser {
    static func pullRequestReference(from url: URL) -> GitHubPullRequestExternalReference? {
        guard url.scheme?.lowercased() == "ruri",
              url.host(percentEncoded: false)?.lowercased() == "github.com" else {
            return nil
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 4,
              components[2] == "pull",
              let number = Int(components[3]),
              number > 0 else {
            return nil
        }

        return GitHubPullRequestExternalReference(
            repository: GitHubRepositoryIdentity(owner: components[0], name: components[1]),
            number: number
        )
    }
}

nonisolated struct ExternalPullRequestWorktreeCreationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let pullRequestNumber: Int
    let repository: GitHubRepositoryIdentity
    let headBranchName: String
    let remoteBranchName: String
    let sourceWorkspaceID: ProjectWorkspaceSnapshot.ID

    init(
        id: UUID = UUID(),
        pullRequestNumber: Int,
        repository: GitHubRepositoryIdentity,
        headBranchName: String,
        remoteBranchName: String,
        sourceWorkspaceID: ProjectWorkspaceSnapshot.ID
    ) {
        self.id = id
        self.pullRequestNumber = pullRequestNumber
        self.repository = repository
        self.headBranchName = headBranchName
        self.remoteBranchName = remoteBranchName
        self.sourceWorkspaceID = sourceWorkspaceID.standardizedFileURL
    }
}
