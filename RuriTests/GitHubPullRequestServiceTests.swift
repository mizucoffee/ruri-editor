//
//  GitHubPullRequestServiceTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class GitHubPullRequestServiceTests: XCTestCase {
    private let ghURL = URL(filePath: "/usr/bin/gh")

    func testPullRequestReturnsOpenPullRequestForBranch() async {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {"number":123,"url":"https://github.com/owner/repo/pull/123","state":"OPEN"}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: "main",
            openedRootURL: rootURL
        )

        XCTAssertEqual(
            status,
            .pullRequest(GitHubPullRequestInfo(
                number: 123,
                url: URL(string: "https://github.com/owner/repo/pull/123")!,
                lifecycleState: .open
            ))
        )
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["pr", "view", "feature/status-pr", "--json", "number,url,state,isDraft"]
        ])
        XCTAssertEqual(calls.first?.currentDirectoryURL, rootURL.standardizedFileURL)
    }

    func testPullRequestRejectsDashPrefixedBranchNameWithoutRunningCommand() async {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "--repo=attacker/repo",
            baseBranch: "main",
            openedRootURL: rootURL
        )

        XCTAssertNil(status)
        let calls = await runner.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testPullRequestReturnsDraftPullRequestForDraftPullRequest() async {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {"number":123,"url":"https://github.com/owner/repo/pull/123","state":"OPEN","isDraft":true}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: "main",
            openedRootURL: rootURL
        )

        XCTAssertEqual(
            status,
            .pullRequest(GitHubPullRequestInfo(
                number: 123,
                url: URL(string: "https://github.com/owner/repo/pull/123")!,
                isDraft: true,
                lifecycleState: .open
            ))
        )
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["pr", "view", "feature/status-pr", "--json", "number,url,state,isDraft"]
        ])
    }

    func testPullRequestReturnsClosedPullRequestForClosedPullRequest() async {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {"number":123,"url":"https://github.com/owner/repo/pull/123","state":"CLOSED"}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: "main",
            openedRootURL: rootURL
        )

        XCTAssertEqual(
            status,
            .pullRequest(GitHubPullRequestInfo(
                number: 123,
                url: URL(string: "https://github.com/owner/repo/pull/123")!,
                lifecycleState: .closed
            ))
        )
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["pr", "view", "feature/status-pr", "--json", "number,url,state,isDraft"]
        ])
    }

    func testPullRequestReturnsMergedPullRequestForMergedPullRequest() async {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {"number":123,"url":"https://github.com/owner/repo/pull/123","state":"MERGED"}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: "main",
            openedRootURL: rootURL
        )

        XCTAssertEqual(
            status,
            .pullRequest(GitHubPullRequestInfo(
                number: 123,
                url: URL(string: "https://github.com/owner/repo/pull/123")!,
                lifecycleState: .merged
            ))
        )
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["pr", "view", "feature/status-pr", "--json", "number,url,state,isDraft"]
        ])
    }

    func testPullRequestReturnsCreationLinkWhenNoPullRequestExists() async {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("no pull requests found for branch"), exitCode: 1)),
            .success(GitHubCommandResult(stdout: data("""
            {"url":"https://github.com/owner/repo/"}
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: "main",
            openedRootURL: rootURL
        )

        XCTAssertEqual(
            status,
            .create(GitHubPullRequestCreationLink(
                baseBranch: "main",
                headBranch: "feature/status-pr",
                url: URL(string: "https://github.com/owner/repo/compare/main...feature/status-pr?expand=1")!
            ))
        )
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["pr", "view", "feature/status-pr", "--json", "number,url,state,isDraft"],
            ["repo", "view", "--json", "url"]
        ])
        XCTAssertEqual(calls.map(\.currentDirectoryURL), [
            rootURL.standardizedFileURL,
            rootURL.standardizedFileURL
        ])
    }

    func testPullRequestReturnsNilWhenNoPullRequestExistsWithoutBaseBranch() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("no pull requests found for branch"), exitCode: 1))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let status = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: nil,
            openedRootURL: URL(filePath: "/tmp/ruri-pr-service")
        )

        XCTAssertNil(status)
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["pr", "view", "feature/status-pr", "--json", "number,url,state,isDraft"]
        ])
    }

    func testPullRequestReturnsNilWhenOptionalGitHubFeatureIsIgnored() async {
        let runner = RecordingGitHubCommandRunner()
        let service = GitHubPullRequestService(executableURL: nil, commandRunner: runner)

        let pullRequest = await service.pullRequestStatus(
            forBranch: "feature/status-pr",
            baseBranch: "main",
            openedRootURL: URL(filePath: "/tmp/ruri-pr-service")
        )

        XCTAssertNil(pullRequest)
        let calls = await runner.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testPullRequestDetailsReturnsBranchAndRepository() async throws {
        let rootURL = URL(filePath: "/tmp/ruri-pr-service", directoryHint: .isDirectory)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("""
            {
              "number":123,
              "url":"https://github.com/owner/repo/pull/123",
              "state":"OPEN",
              "headRefName":"feature/status-pr",
              "baseRefName":"main",
              "headRepositoryOwner":{"login":"owner"},
              "headRepository":{"name":"repo"}
            }
            """), exitCode: 0))
        ])
        let service = GitHubPullRequestService(executableURL: ghURL, commandRunner: runner)

        let details = try await service.pullRequestDetails(number: 123, openedRootURL: rootURL)

        XCTAssertEqual(details, GitHubPullRequestDetails(
            number: 123,
            url: URL(string: "https://github.com/owner/repo/pull/123")!,
            state: "OPEN",
            headBranchName: "feature/status-pr",
            baseBranchName: "main",
            headRepository: GitHubRepositoryIdentity(owner: "owner", name: "repo")
        ))
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            [
                "pr",
                "view",
                "123",
                "--json",
                "number,url,state,headRefName,baseRefName,headRepositoryOwner,headRepository"
            ]
        ])
        XCTAssertEqual(calls.first?.currentDirectoryURL, rootURL.standardizedFileURL)
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}
