//
//  GitHubAuthViewModelTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class GitHubAuthViewModelTests: XCTestCase {
    func testRefreshPublishesAuthenticatedStatus() async {
        let service = SequenceGitHubAuthService(statuses: [
            .authenticated(username: "mizucoffee")
        ])
        let viewModel = GitHubAuthViewModel(service: service)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.status, .authenticated(username: "mizucoffee"))
    }

    func testLogInIgnoresDuplicateRequestsWhileAuthenticating() async {
        let service = BlockingGitHubAuthService(statusAfterLogin: .authenticated(username: "mizucoffee"))
        let viewModel = GitHubAuthViewModel(service: service)

        let firstTask = Task { @MainActor in
            await viewModel.logIn()
        }
        await service.waitForLoginCallCount(1)

        let secondTask = Task { @MainActor in
            await viewModel.logIn()
        }
        await Task.yield()

        let loginCallCountBeforeCompletion = await service.loginCallCount()
        XCTAssertEqual(loginCallCountBeforeCompletion, 1)
        await service.completeLogin()
        await firstTask.value
        await secondTask.value

        let loginCallCountAfterCompletion = await service.loginCallCount()
        XCTAssertEqual(loginCallCountAfterCompletion, 1)
        XCTAssertEqual(viewModel.status, .authenticated(username: "mizucoffee"))
    }

    func testFailedLogInPublishesErrorAndRefreshesStatus() async {
        let service = SequenceGitHubAuthService(
            statuses: [.unauthenticated],
            loginResults: [.failure(TestError.loginFailed)]
        )
        let viewModel = GitHubAuthViewModel(service: service)

        await viewModel.logIn()

        XCTAssertEqual(viewModel.status, .unauthenticated)
        XCTAssertEqual(viewModel.currentError?.message, "Login failed.")
    }

    func testLogInPublishesPromptOpensBrowserAndCopiesCode() async {
        let prompt = GitHubLoginDevicePrompt(
            userCode: "5A50-2869",
            verificationURL: URL(string: "https://github.com/login/device")!
        )
        let service = SequenceGitHubAuthService(
            statuses: [.authenticated(username: "mizucoffee")],
            loginPrompts: [prompt]
        )
        let browserOpener = RecordingGitHubLoginBrowserOpener()
        let codeCopier = RecordingGitHubLoginCodeCopier()
        let viewModel = GitHubAuthViewModel(
            service: service,
            browserOpener: browserOpener,
            codeCopier: codeCopier
        )

        await viewModel.logIn()

        XCTAssertEqual(viewModel.loginDevicePrompt, prompt)
        XCTAssertEqual(browserOpener.openedURLs, [prompt.verificationURL])
        XCTAssertEqual(codeCopier.copiedCodes, [prompt.userCode])
        XCTAssertEqual(viewModel.status, .authenticated(username: "mizucoffee"))
    }
}

private actor SequenceGitHubAuthService: GitHubAuthServiceProtocol {
    private var statuses: [GitHubAuthStatusState]
    private var loginResults: [Result<Void, Error>]
    private var loginPrompts: [GitHubLoginDevicePrompt]

    init(
        statuses: [GitHubAuthStatusState],
        loginResults: [Result<Void, Error>] = [],
        loginPrompts: [GitHubLoginDevicePrompt] = []
    ) {
        self.statuses = statuses
        self.loginResults = loginResults
        self.loginPrompts = loginPrompts
    }

    func currentAuthenticationStatus() async -> GitHubAuthStatusState {
        statuses.isEmpty ? .unauthenticated : statuses.removeFirst()
    }

    func logIn(
        devicePromptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void
    ) async throws {
        if !loginPrompts.isEmpty {
            devicePromptHandler(loginPrompts.removeFirst())
        }
        let result = loginResults.isEmpty ? .success(()) : loginResults.removeFirst()
        try result.get()
    }
}

private actor BlockingGitHubAuthService: GitHubAuthServiceProtocol {
    private let statusAfterLogin: GitHubAuthStatusState
    private var storedLoginCallCount = 0
    private var loginContinuation: CheckedContinuation<Void, Error>?

    init(statusAfterLogin: GitHubAuthStatusState) {
        self.statusAfterLogin = statusAfterLogin
    }

    func currentAuthenticationStatus() async -> GitHubAuthStatusState {
        statusAfterLogin
    }

    func logIn(
        devicePromptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void
    ) async throws {
        storedLoginCallCount += 1
        try await withCheckedThrowingContinuation { continuation in
            loginContinuation = continuation
        }
    }

    func loginCallCount() -> Int {
        storedLoginCallCount
    }

    func waitForLoginCallCount(_ expectedCount: Int) async {
        while storedLoginCallCount < expectedCount {
            await Task.yield()
        }
    }

    func completeLogin() {
        loginContinuation?.resume()
        loginContinuation = nil
    }
}

@MainActor
private final class RecordingGitHubLoginBrowserOpener: GitHubLoginBrowserOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}

@MainActor
private final class RecordingGitHubLoginCodeCopier: GitHubLoginCodeCopying {
    private(set) var copiedCodes: [String] = []

    func copy(_ code: String) {
        copiedCodes.append(code)
    }
}

private enum TestError: LocalizedError {
    case loginFailed

    var errorDescription: String? {
        switch self {
        case .loginFailed:
            "Login failed."
        }
    }
}
