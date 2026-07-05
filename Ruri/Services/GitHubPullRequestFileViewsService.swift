//
//  GitHubPullRequestFileViewsService.swift
//  ruri
//

import Foundation

nonisolated protocol GitHubPullRequestFileViewsServiceProtocol: Sendable {
    func fileViews(
        pullRequestNumber: Int,
        openedRootURL: URL
    ) async -> GitHubPullRequestFileViewsResult
    func setFileViewed(
        _ viewed: Bool,
        pullRequestNodeID: String,
        path: String,
        openedRootURL: URL
    ) async throws
}

nonisolated struct GitHubPullRequestFileViewsService: GitHubPullRequestFileViewsServiceProtocol, Sendable {
    private static let filesPageSize = 100
    private static let maxFilesPages = 20

    private static let fileViewsQuery = """
    query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          id
          files(first: \(filesPageSize), after: $cursor) {
            pageInfo { hasNextPage endCursor }
            nodes { path viewerViewedState }
          }
        }
      }
    }
    """

    private static let markFileAsViewedMutation = """
    mutation($id: ID!, $path: String!) {
      markFileAsViewed(input: { pullRequestId: $id, path: $path }) {
        pullRequest { id }
      }
    }
    """

    private static let unmarkFileAsViewedMutation = """
    mutation($id: ID!, $path: String!) {
      unmarkFileAsViewed(input: { pullRequestId: $id, path: $path }) {
        pullRequest { id }
      }
    }
    """

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

    func fileViews(
        pullRequestNumber: Int,
        openedRootURL: URL
    ) async -> GitHubPullRequestFileViewsResult {
        guard pullRequestNumber > 0 else {
            return .failed(GitHubPullRequestFileViewsError.invalidPullRequestNumber(pullRequestNumber).localizedDescription)
        }

        var pullRequestNodeID: String?
        var statesByPath: [String: GitHubPullRequestFileViewedState] = [:]
        var cursor: String?

        for _ in 0..<Self.maxFilesPages {
            var arguments = [
                "api",
                "graphql",
                "-f",
                "query=\(Self.fileViewsQuery)",
                "-F",
                "owner={owner}",
                "-F",
                "name={repo}",
                "-F",
                "number=\(pullRequestNumber)"
            ]
            if let cursor {
                arguments += ["-F", "cursor=\(cursor)"]
            }

            let result = await cliClient.runOptionalFeatureCommand(
                arguments: arguments,
                currentDirectoryURL: openedRootURL.standardizedFileURL
            )

            switch result {
            case .success(let commandResult):
                guard let page = Self.fileViewsPage(from: commandResult.stdout) else {
                    return .failed(GitHubPullRequestFileViewsError.invalidResponse.localizedDescription)
                }

                pullRequestNodeID = page.pullRequestNodeID
                statesByPath.merge(page.statesByPath) { _, new in new }

                guard page.hasNextPage, let endCursor = page.endCursor else {
                    return .available(GitHubPullRequestFileViews(
                        pullRequestNodeID: page.pullRequestNodeID,
                        statesByPath: statesByPath
                    ))
                }
                cursor = endCursor

            case .ignored(let reason):
                return .ignored(reason)

            case .failed(let message):
                return .failed(message)
            }
        }

        guard let pullRequestNodeID else {
            return .failed(GitHubPullRequestFileViewsError.invalidResponse.localizedDescription)
        }

        // ページ上限到達: ここまでに取得できた分だけ返す。
        return .available(GitHubPullRequestFileViews(
            pullRequestNodeID: pullRequestNodeID,
            statesByPath: statesByPath
        ))
    }

    func setFileViewed(
        _ viewed: Bool,
        pullRequestNodeID: String,
        path: String,
        openedRootURL: URL
    ) async throws {
        let trimmedNodeID = pullRequestNodeID.trimmingCharacters(in: .whitespacesAndNewlines)
        // "-" 始まりの値はghにフラグとして解釈されるため渡さない。
        guard !trimmedNodeID.isEmpty, !trimmedNodeID.hasPrefix("-") else {
            throw GitHubPullRequestFileViewsError.invalidPullRequestNodeID(pullRequestNodeID)
        }

        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedPath.hasPrefix("-") else {
            throw GitHubPullRequestFileViewsError.invalidPath(path)
        }

        let mutation = viewed ? Self.markFileAsViewedMutation : Self.unmarkFileAsViewedMutation
        let result = try await cliClient.run(
            arguments: [
                "api",
                "graphql",
                "-f",
                "query=\(mutation)",
                "-F",
                "id=\(trimmedNodeID)",
                "-F",
                "path=\(trimmedPath)"
            ],
            currentDirectoryURL: openedRootURL.standardizedFileURL
        )

        guard result.exitCode == 0 else {
            throw GitHubPullRequestFileViewsError.commandFailed(GitHubCLIClient.commandErrorMessage(from: result))
        }
    }

    private static func fileViewsPage(from data: Data) -> FileViewsPage? {
        guard let response = try? JSONDecoder().decode(FileViewsResponse.self, from: data),
              let pullRequest = response.data.repository?.pullRequest,
              !pullRequest.id.isEmpty else {
            return nil
        }

        var statesByPath: [String: GitHubPullRequestFileViewedState] = [:]
        for node in pullRequest.files.nodes {
            guard !node.path.isEmpty else { continue }
            statesByPath[node.path] = GitHubPullRequestFileViewedState(rawValue: node.viewerViewedState) ?? .unviewed
        }

        return FileViewsPage(
            pullRequestNodeID: pullRequest.id,
            statesByPath: statesByPath,
            hasNextPage: pullRequest.files.pageInfo.hasNextPage,
            endCursor: pullRequest.files.pageInfo.endCursor
        )
    }

    private struct FileViewsPage {
        let pullRequestNodeID: String
        let statesByPath: [String: GitHubPullRequestFileViewedState]
        let hasNextPage: Bool
        let endCursor: String?
    }
}

private struct FileViewsResponse: Decodable {
    let data: FileViewsDataResponse
}

private struct FileViewsDataResponse: Decodable {
    let repository: FileViewsRepositoryResponse?
}

private struct FileViewsRepositoryResponse: Decodable {
    let pullRequest: FileViewsPullRequestResponse?
}

private struct FileViewsPullRequestResponse: Decodable {
    let id: String
    let files: FileViewsConnectionResponse
}

private struct FileViewsConnectionResponse: Decodable {
    let pageInfo: FileViewsPageInfoResponse
    let nodes: [FileViewsFileResponse]
}

private struct FileViewsPageInfoResponse: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct FileViewsFileResponse: Decodable {
    let path: String
    let viewerViewedState: String
}
