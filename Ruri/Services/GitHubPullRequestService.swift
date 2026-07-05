//
//  GitHubPullRequestService.swift
//  ruri
//

import Foundation

nonisolated protocol GitHubPullRequestServiceProtocol: Sendable {
    func pullRequestStatus(
        forBranch branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async -> GitHubPullRequestStatus?
    func pullRequestDetails(
        number: Int,
        openedRootURL: URL
    ) async throws -> GitHubPullRequestDetails
}

nonisolated struct GitHubPullRequestService: GitHubPullRequestServiceProtocol, Sendable {
    private let cliClient: GitHubCLIClient

    init(
        executableURL: URL? = GitHubExecutableResolver().executableURL(named: "gh"),
        commandRunner: any GitHubCommandRunning = ProcessGitHubCommandRunner(),
        commandTimeout: TimeInterval = 20
    ) {
        cliClient = GitHubCLIClient(
            executableURL: executableURL,
            commandRunner: commandRunner,
            commandTimeout: commandTimeout
        )
    }

    func pullRequestStatus(
        forBranch branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async -> GitHubPullRequestStatus? {
        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        // "-" 始まりのref名はghにフラグとして解釈されるため、位置引数として渡さない。
        guard !trimmedBranchName.isEmpty, !trimmedBranchName.hasPrefix("-") else { return nil }

        let result = await cliClient.runOptionalFeatureCommand(
            arguments: [
                "pr",
                "view",
                trimmedBranchName,
                "--json",
                "number,url,state,isDraft,mergeable"
            ],
            currentDirectoryURL: openedRootURL.standardizedFileURL
        )

        switch result {
        case .success(let commandResult):
            if let pullRequest = Self.pullRequest(from: commandResult.stdout) {
                return .pullRequest(pullRequest)
            }

            return await creationStatus(
                forBranch: trimmedBranchName,
                baseBranch: baseBranch,
                openedRootURL: openedRootURL
            )

        case .ignored:
            return nil

        case .failed(let message):
            if Self.isNoPullRequestMessage(message) {
                return await creationStatus(
                    forBranch: trimmedBranchName,
                    baseBranch: baseBranch,
                    openedRootURL: openedRootURL
                )
            }

            return nil
        }
    }

    func pullRequestDetails(
        number: Int,
        openedRootURL: URL
    ) async throws -> GitHubPullRequestDetails {
        guard number > 0 else {
            throw GitHubPullRequestServiceError.invalidPullRequestNumber(number)
        }

        let result = try await cliClient.run(
            arguments: [
                "pr",
                "view",
                String(number),
                "--json",
                "number,url,state,headRefName,baseRefName,headRepositoryOwner,headRepository"
            ],
            currentDirectoryURL: openedRootURL.standardizedFileURL
        )
        guard result.exitCode == 0 else {
            throw GitHubPullRequestServiceError.commandFailed(GitHubCLIClient.commandErrorMessage(from: result))
        }

        guard let details = Self.pullRequestDetails(from: result.stdout) else {
            throw GitHubPullRequestServiceError.invalidResponse
        }

        return details
    }

    private func creationStatus(
        forBranch branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async -> GitHubPullRequestStatus? {
        guard let baseBranch = baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseBranch.isEmpty,
              baseBranch != branchName else {
            return nil
        }

        let result = await cliClient.runOptionalFeatureCommand(
            arguments: ["repo", "view", "--json", "url"],
            currentDirectoryURL: openedRootURL.standardizedFileURL
        )

        guard case .success(let commandResult) = result,
              let repositoryURL = Self.repositoryURL(from: commandResult.stdout),
              let creationURL = Self.pullRequestCreationURL(
                repositoryURL: repositoryURL,
                baseBranch: baseBranch,
                headBranch: branchName
              ) else {
            return nil
        }

        return .create(GitHubPullRequestCreationLink(
            baseBranch: baseBranch,
            headBranch: branchName,
            url: creationURL
        ))
    }

    private static func pullRequest(from data: Data) -> GitHubPullRequestInfo? {
        guard let response = try? JSONDecoder().decode(PullRequestResponse.self, from: data),
              let url = URL(string: response.url) else {
            return nil
        }

        return GitHubPullRequestInfo(
            number: response.number,
            url: url,
            isDraft: response.isDraft ?? false,
            lifecycleState: GitHubPullRequestLifecycleState(rawValue: response.state),
            mergeableState: GitHubPullRequestMergeableState(rawValue: response.mergeable ?? "")
        )
    }

    private static func pullRequestDetails(from data: Data) -> GitHubPullRequestDetails? {
        guard let response = try? JSONDecoder().decode(PullRequestDetailsResponse.self, from: data),
              let url = URL(string: response.url),
              !response.headRefName.isEmpty,
              !response.baseRefName.isEmpty,
              !response.headRepository.name.isEmpty,
              !response.headRepositoryOwner.login.isEmpty else {
            return nil
        }

        return GitHubPullRequestDetails(
            number: response.number,
            url: url,
            state: response.state,
            headBranchName: response.headRefName,
            baseBranchName: response.baseRefName,
            headRepository: GitHubRepositoryIdentity(
                owner: response.headRepositoryOwner.login,
                name: response.headRepository.name
            )
        )
    }

    private static func repositoryURL(from data: Data) -> URL? {
        guard let response = try? JSONDecoder().decode(RepositoryResponse.self, from: data) else {
            return nil
        }

        return URL(string: response.url)
    }

    private static func pullRequestCreationURL(
        repositoryURL: URL,
        baseBranch: String,
        headBranch: String
    ) -> URL? {
        let repositoryURLString = repositoryURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(repositoryURLString)/compare/\(baseBranch)...\(headBranch)") else {
            return nil
        }

        components.queryItems = [URLQueryItem(name: "expand", value: "1")]
        return components.url
    }

    private static func isNoPullRequestMessage(_ message: String) -> Bool {
        let lowercasedMessage = message.lowercased()
        return lowercasedMessage.contains("no pull requests found")
            || lowercasedMessage.contains("no pull request found")
            || lowercasedMessage.contains("could not find a pull request")
    }
}

nonisolated enum GitHubPullRequestServiceError: LocalizedError, Equatable {
    case invalidPullRequestNumber(Int)
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidPullRequestNumber(let number):
            "Invalid GitHub pull request number: \(number)."
        case .commandFailed(let message):
            message.isEmpty ? "GitHub pull request lookup failed." : message
        case .invalidResponse:
            "GitHub returned an invalid pull request response."
        }
    }
}

private struct PullRequestResponse: Decodable {
    let number: Int
    let url: String
    let state: String
    let isDraft: Bool?
    let mergeable: String?
}

private struct PullRequestDetailsResponse: Decodable {
    let number: Int
    let url: String
    let state: String
    let headRefName: String
    let baseRefName: String
    let headRepositoryOwner: RepositoryOwnerResponse
    let headRepository: RepositoryNameResponse
}

private struct RepositoryOwnerResponse: Decodable {
    let login: String
}

private struct RepositoryNameResponse: Decodable {
    let name: String
}

private struct RepositoryResponse: Decodable {
    let url: String
}
