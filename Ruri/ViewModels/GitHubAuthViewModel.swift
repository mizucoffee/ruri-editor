//
//  GitHubAuthViewModel.swift
//  ruri
//

import AppKit
import Combine
import Foundation

@MainActor
final class GitHubAuthViewModel: ObservableObject {
    @Published private(set) var status: GitHubAuthStatusState
    @Published private(set) var currentError: EditorError?
    @Published private(set) var loginDevicePrompt: GitHubLoginDevicePrompt?

    private let service: any GitHubAuthServiceProtocol
    private let browserOpener: any GitHubLoginBrowserOpening
    private let codeCopier: any GitHubLoginCodeCopying
    private var isRefreshing = false
    private var isLoggingIn = false

    init(
        service: any GitHubAuthServiceProtocol = GitHubAuthService(),
        browserOpener: (any GitHubLoginBrowserOpening)? = nil,
        codeCopier: (any GitHubLoginCodeCopying)? = nil,
        initialStatus: GitHubAuthStatusState = .checking
    ) {
        self.service = service
        self.browserOpener = browserOpener ?? WorkspaceGitHubLoginBrowserOpener()
        self.codeCopier = codeCopier ?? PasteboardGitHubLoginCodeCopier()
        status = initialStatus
    }

    var errorMessage: String? {
        currentError?.message
    }

    func refresh() async {
        guard !isRefreshing,
              !isLoggingIn else {
            return
        }

        isRefreshing = true
        status = .checking
        let refreshedStatus = await service.currentAuthenticationStatus()
        status = refreshedStatus
        isRefreshing = false
    }

    func logIn() async {
        guard !isLoggingIn else { return }

        isLoggingIn = true
        currentError = nil
        status = .authenticating

        do {
            try await service.logIn { [weak self] prompt in
                Task { @MainActor [weak self] in
                    self?.handleLoginDevicePrompt(prompt)
                }
            }
        } catch {
            currentError = EditorError(error)
        }

        isLoggingIn = false
        await refresh()
    }

    func clearError() {
        currentError = nil
    }

    func clearLoginDevicePrompt() {
        loginDevicePrompt = nil
    }

    private func handleLoginDevicePrompt(_ prompt: GitHubLoginDevicePrompt) {
        loginDevicePrompt = prompt
        codeCopier.copy(prompt.userCode)
        browserOpener.open(prompt.verificationURL)
    }
}

@MainActor
protocol GitHubLoginBrowserOpening: Sendable {
    func open(_ url: URL)
}

struct WorkspaceGitHubLoginBrowserOpener: GitHubLoginBrowserOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
protocol GitHubLoginCodeCopying: Sendable {
    func copy(_ code: String)
}

struct PasteboardGitHubLoginCodeCopier: GitHubLoginCodeCopying {
    func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}
