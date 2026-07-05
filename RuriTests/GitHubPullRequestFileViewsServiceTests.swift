//
//  GitHubPullRequestFileViewsServiceTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class GitHubPullRequestFileViewsServiceTests: XCTestCase {
    private let ghURL = URL(filePath: "/usr/bin/gh")
    private let rootURL = URL(filePath: "/tmp/ruri-pr-file-views", directoryHint: .isDirectory)

    func testFileViewsReturnsStatesByPath() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {"data":{"repository":{"pullRequest":{"id":"PR_node","files":{"pageInfo":{"hasNextPage":false,"endCursor":"MTE"},"nodes":[{"path":"Sources/App.swift","viewerViewedState":"VIEWED"},{"path":"Sources/Other.swift","viewerViewedState":"UNVIEWED"},{"path":"Sources/Old.swift","viewerViewedState":"DISMISSED"}]}}}}}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        let result = await service.fileViews(pullRequestNumber: 42, openedRootURL: rootURL)

        guard case .available(let views) = result else {
            return XCTFail("Expected available result, got \(result)")
        }
        XCTAssertEqual(views.pullRequestNodeID, "PR_node")
        XCTAssertEqual(views.statesByPath, [
            "Sources/App.swift": .viewed,
            "Sources/Other.swift": .unviewed,
            "Sources/Old.swift": .dismissed
        ])

        let calls = await runner.calls()
        XCTAssertEqual(calls.count, 1)
        let arguments = calls[0].arguments
        XCTAssertEqual(arguments.prefix(2), ["api", "graphql"])
        XCTAssertTrue(arguments.contains("owner={owner}"))
        XCTAssertTrue(arguments.contains("name={repo}"))
        XCTAssertTrue(arguments.contains("number=42"))
        XCTAssertTrue(arguments.contains { $0.hasPrefix("query=") && $0.contains("viewerViewedState") })
        XCTAssertFalse(arguments.contains { $0.hasPrefix("cursor=") })
        XCTAssertEqual(calls[0].currentDirectoryURL, rootURL.standardizedFileURL)
    }

    func testFileViewsFollowsPagination() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {"data":{"repository":{"pullRequest":{"id":"PR_node","files":{"pageInfo":{"hasNextPage":true,"endCursor":"CURSOR1"},"nodes":[{"path":"First.swift","viewerViewedState":"VIEWED"}]}}}}}
            """), exitCode: 0)),
            .success(GitHubCommandResult(stdout: data("""
            {"data":{"repository":{"pullRequest":{"id":"PR_node","files":{"pageInfo":{"hasNextPage":false,"endCursor":"CURSOR2"},"nodes":[{"path":"Second.swift","viewerViewedState":"UNVIEWED"}]}}}}}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        let result = await service.fileViews(pullRequestNumber: 7, openedRootURL: rootURL)

        guard case .available(let views) = result else {
            return XCTFail("Expected available result, got \(result)")
        }
        XCTAssertEqual(views.statesByPath, [
            "First.swift": .viewed,
            "Second.swift": .unviewed
        ])

        let calls = await runner.calls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertFalse(calls[0].arguments.contains { $0.hasPrefix("cursor=") })
        XCTAssertTrue(calls[1].arguments.contains("cursor=CURSOR1"))
    }

    func testFileViewsReturnsIgnoredWhenUnauthenticated() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(
                stderr: data("To get started with GitHub CLI, please run: gh auth login"),
                exitCode: 1
            ))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        let result = await service.fileViews(pullRequestNumber: 42, openedRootURL: rootURL)

        XCTAssertEqual(result, .ignored(.unauthenticated))
    }

    func testFileViewsReturnsIgnoredWhenGitHubCLIIsNotInstalled() async {
        let service = GitHubPullRequestFileViewsService(
            executableURL: nil,
            commandRunner: RecordingGitHubCommandRunner(results: [])
        )

        let result = await service.fileViews(pullRequestNumber: 42, openedRootURL: rootURL)

        XCTAssertEqual(result, .ignored(.githubCLINotInstalled))
    }

    func testFileViewsReturnsFailedOnInvalidResponse() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("{\"data\":{\"repository\":null}}"), exitCode: 0))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        let result = await service.fileViews(pullRequestNumber: 42, openedRootURL: rootURL)

        guard case .failed = result else {
            return XCTFail("Expected failed result, got \(result)")
        }
    }

    func testSetFileViewedRunsMarkMutation() async throws {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("{}"), exitCode: 0))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        try await service.setFileViewed(
            true,
            pullRequestNodeID: "PR_node",
            path: "Sources/App.swift",
            openedRootURL: rootURL
        )

        let calls = await runner.calls()
        XCTAssertEqual(calls.count, 1)
        let arguments = calls[0].arguments
        XCTAssertEqual(arguments.prefix(2), ["api", "graphql"])
        XCTAssertTrue(arguments.contains { $0.hasPrefix("query=") && $0.contains("markFileAsViewed") })
        XCTAssertTrue(arguments.contains("id=PR_node"))
        XCTAssertTrue(arguments.contains("path=Sources/App.swift"))
    }

    func testSetFileViewedRunsUnmarkMutation() async throws {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("{}"), exitCode: 0))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        try await service.setFileViewed(
            false,
            pullRequestNodeID: "PR_node",
            path: "Sources/App.swift",
            openedRootURL: rootURL
        )

        let calls = await runner.calls()
        XCTAssertTrue(calls[0].arguments.contains { $0.hasPrefix("query=") && $0.contains("unmarkFileAsViewed") })
    }

    func testSetFileViewedThrowsOnCommandFailure() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("GraphQL: Could not resolve to a node"), exitCode: 1))
        ])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        do {
            try await service.setFileViewed(
                true,
                pullRequestNodeID: "PR_node",
                path: "Sources/App.swift",
                openedRootURL: rootURL
            )
            XCTFail("Expected setFileViewed to throw")
        } catch let error as GitHubPullRequestFileViewsError {
            XCTAssertEqual(error, .commandFailed("GraphQL: Could not resolve to a node"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSetFileViewedRejectsDashPrefixedValuesWithoutRunningCommand() async {
        let runner = RecordingGitHubCommandRunner(results: [])
        let service = GitHubPullRequestFileViewsService(executableURL: ghURL, commandRunner: runner)

        await XCTAssertThrowsErrorAsync(
            try await service.setFileViewed(
                true,
                pullRequestNodeID: "--repo=attacker/repo",
                path: "Sources/App.swift",
                openedRootURL: rootURL
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await service.setFileViewed(
                true,
                pullRequestNodeID: "PR_node",
                path: "--attack",
                openedRootURL: rootURL
            )
        )

        let calls = await runner.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // expected
    }
}
