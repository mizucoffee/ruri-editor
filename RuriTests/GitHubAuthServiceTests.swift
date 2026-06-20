//
//  GitHubAuthServiceTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class GitHubAuthServiceTests: XCTestCase {
    private let ghURL = URL(filePath: "/usr/bin/gh")

    func testCurrentAuthenticationStatusReportsUnavailableWhenGitHubCLIIsMissing() async {
        let runner = FakeGitHubCommandRunner()
        let service = GitHubAuthService(executableURL: nil, commandRunner: runner)

        let status = await service.currentAuthenticationStatus()

        XCTAssertEqual(status, .unavailable(message: "GitHub CLI is not installed."))
        let calls = await runner.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCurrentAuthenticationStatusReportsAuthenticatedUsername() async {
        let runner = FakeGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stdout: data("mizucoffee\n"), exitCode: 0))
        ])
        let service = GitHubAuthService(
            executableURL: ghURL,
            commandRunner: runner,
            loginCommandTimeout: 300
        )

        let status = await service.currentAuthenticationStatus()

        XCTAssertEqual(status, .authenticated(username: "mizucoffee"))
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            ["api", "user", "--hostname", "github.com", "--jq", ".login"]
        ])
    }

    func testCurrentAuthenticationStatusReportsUnauthenticatedForInvalidToken() async {
        let runner = FakeGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("HTTP 401: Bad credentials"), exitCode: 1))
        ])
        let service = GitHubAuthService(executableURL: ghURL, commandRunner: runner)

        let status = await service.currentAuthenticationStatus()

        XCTAssertEqual(status, .unauthenticated)
    }

    func testCurrentAuthenticationStatusReportsFailureForNetworkErrors() async {
        let runner = FakeGitHubCommandRunner(results: [
            .success(GitHubCommandResult(stderr: data("error connecting to api.github.com"), exitCode: 1))
        ])
        let service = GitHubAuthService(executableURL: ghURL, commandRunner: runner)

        let status = await service.currentAuthenticationStatus()

        guard case .failed(let message) = status else {
            return XCTFail("Expected failed status.")
        }
        XCTAssertEqual(message, "error connecting to api.github.com")
    }

    func testLogInRunsGitHubCLIAndCanRefreshAuthenticatedState() async throws {
        let runner = FakeGitHubCommandRunner(results: [
            .success(GitHubCommandResult(exitCode: 0)),
            .success(GitHubCommandResult(stdout: data("mizucoffee\n"), exitCode: 0))
        ])
        let service = GitHubAuthService(executableURL: ghURL, commandRunner: runner)

        try await service.logIn { _ in }
        let status = await service.currentAuthenticationStatus()

        XCTAssertEqual(status, .authenticated(username: "mizucoffee"))
        let calls = await runner.calls()
        XCTAssertEqual(calls.map(\.arguments), [
            [
                "auth",
                "login",
                "--hostname",
                "github.com",
                "--web",
                "--git-protocol",
                "ssh",
                "--skip-ssh-key"
            ],
            ["api", "user", "--hostname", "github.com", "--jq", ".login"]
        ])
        XCTAssertEqual(calls.first?.environment, ["GH_BROWSER": "/usr/bin/open"])
        XCTAssertEqual(calls.first?.standardInput, data("\n"))
        XCTAssertEqual(calls.first?.timeout, 300)
    }

    func testLogInReportsDevicePromptFromGitHubCLIOutput() async throws {
        let runner = FakeGitHubCommandRunner(results: [
            .success(GitHubCommandResult(exitCode: 0))
        ])
        let service = GitHubAuthService(executableURL: ghURL, commandRunner: runner)
        let promptStore = GitHubPromptStore()

        try await service.logIn { prompt in
            promptStore.append(prompt)
        }

        XCTAssertEqual(promptStore.prompts(), [
            GitHubLoginDevicePrompt(
                userCode: "5A50-2869",
                verificationURL: URL(string: "https://github.com/login/device")!
            )
        ])
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}

private actor FakeGitHubCommandRunner: GitHubCommandRunning {
    struct Call: Equatable {
        let executableURL: URL
        let arguments: [String]
        let currentDirectoryURL: URL?
        let environment: [String: String]
        let standardInput: Data?
        let outputHandler: (@Sendable (Data) -> Void)?
        let timeout: TimeInterval

        static func == (lhs: Call, rhs: Call) -> Bool {
            lhs.executableURL == rhs.executableURL
                && lhs.arguments == rhs.arguments
                && lhs.currentDirectoryURL == rhs.currentDirectoryURL
                && lhs.environment == rhs.environment
                && lhs.standardInput == rhs.standardInput
                && lhs.timeout == rhs.timeout
        }
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
            outputHandler: outputHandler,
            timeout: timeout
        ))
        if arguments.starts(with: ["auth", "login"]) {
            outputHandler?(Data("""
            ! First copy your one-time code: 5A50-2869
            Open this URL to continue in your web browser: https://github.com/login/device
            """.utf8))
        }
        let result = storedResults.isEmpty
            ? .success(GitHubCommandResult(exitCode: 0))
            : storedResults.removeFirst()

        return try result.get()
    }

    func calls() -> [Call] {
        storedCalls
    }
}

private final class GitHubPromptStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPrompts: [GitHubLoginDevicePrompt] = []

    func append(_ prompt: GitHubLoginDevicePrompt) {
        lock.lock()
        storedPrompts.append(prompt)
        lock.unlock()
    }

    func prompts() -> [GitHubLoginDevicePrompt] {
        lock.lock()
        let prompts = storedPrompts
        lock.unlock()
        return prompts
    }
}
