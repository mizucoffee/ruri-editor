//
//  GitHubCLIClientTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class GitHubCLIClientTests: XCTestCase {
    private let ghURL = URL(filePath: "/usr/bin/gh")

    func testOptionalFeatureCommandIgnoresMissingGitHubCLI() async {
        let runner = RecordingGitHubCommandRunner()
        let client = GitHubCLIClient(executableURL: nil, commandRunner: runner)

        let result = await client.runOptionalFeatureCommand(arguments: ["pr", "view"])

        XCTAssertEqual(result, .ignored(.githubCLINotInstalled))
        let calls = await runner.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testOptionalFeatureCommandIgnoresUnauthenticatedResult() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("HTTP 401: Bad credentials"), exitCode: 1))
        ])
        let client = GitHubCLIClient(executableURL: ghURL, commandRunner: runner)

        let result = await client.runOptionalFeatureCommand(arguments: ["pr", "view"])

        XCTAssertEqual(result, .ignored(.unauthenticated))
    }

    func testOptionalFeatureCommandReturnsFailedForOtherFailures() async {
        let runner = RecordingGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("api.github.com timed out"), exitCode: 1))
        ])
        let client = GitHubCLIClient(executableURL: ghURL, commandRunner: runner)

        let result = await client.runOptionalFeatureCommand(arguments: ["pr", "view"])

        XCTAssertEqual(result, .failed("api.github.com timed out"))
    }

    func testOptionalFeatureCommandReturnsSuccess() async {
        let commandResult = GitHubCommandResult(stdout: data("{}"), exitCode: 0)
        let runner = RecordingGitHubCommandRunner(results: [
            .success(commandResult)
        ])
        let client = GitHubCLIClient(executableURL: ghURL, commandRunner: runner)

        let result = await client.runOptionalFeatureCommand(arguments: ["pr", "view"])

        XCTAssertEqual(result, .success(commandResult))
    }

    func testOptionalFeatureCommandReturnsFailedWhenExecutableCannotLaunch() async {
        let client = GitHubCLIClient(
            executableURL: URL(filePath: "/tmp/ruri-missing-gh-executable"),
            commandRunner: ProcessGitHubCommandRunner()
        )

        let result = await client.runOptionalFeatureCommand(arguments: ["pr", "view"])

        guard case .failed(let message) = result else {
            return XCTFail("Expected failed result.")
        }
        XCTAssertTrue(message.contains("not executable"))
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}

actor RecordingGitHubCommandRunner: GitHubCommandRunning {
    struct Call: Equatable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
        let environment: [String: String]
        let standardInput: Data?
        let timeout: TimeInterval
    }

    private var storedResults: [Result<GitHubCommandResult, Error>]
    private var storedCalls: [Call] = []

    init(results: [Result<GitHubCommandResult, Error>] = []) {
        storedResults = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String],
        standardInput: Data?,
        outputHandler: (@Sendable (Data) -> Void)?,
        timeout: TimeInterval
    ) async throws -> GitHubCommandResult {
        storedCalls.append(Call(
            executableURL: executableURL,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            environment: environment,
            standardInput: standardInput,
            timeout: timeout
        ))

        let result = storedResults.isEmpty
            ? .success(GitHubCommandResult(exitCode: 0))
            : storedResults.removeFirst()
        return try result.get()
    }

    func calls() -> [Call] {
        storedCalls
    }
}
