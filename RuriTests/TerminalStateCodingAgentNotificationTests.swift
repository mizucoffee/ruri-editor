//
//  TerminalStateCodingAgentNotificationTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

@MainActor
final class TerminalStateCodingAgentNotificationTests: XCTestCase {
    func testNotifiesWhenCodingAgentStartsWaiting() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier)
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )
        let terminalID = try XCTUnwrap(state.tabs.first?.id)
        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                terminalID: makeStatus(
                    terminalID: terminalID,
                    state: .waiting,
                    event: "PermissionRequest"
                )
            ]
        ]

        await state.refreshAgentStatuses()
        try await waitForNotificationDelivery()

        XCTAssertEqual(notifier.notifiedStatuses.map(\.state), [.waiting])
        XCTAssertEqual(notifier.notifiedStatuses.map(\.event), ["PermissionRequest"])
        XCTAssertEqual(notifier.notifiedContexts.map(\.terminalTitle), ["Terminal 1"])
        XCTAssertEqual(notifier.notifiedContexts.map(\.workspaceName), ["Project"])
    }

    func testDoesNotNotifyRepeatedCodingAgentStatus() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier)
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )
        let terminalID = try XCTUnwrap(state.tabs.first?.id)
        let status = makeStatus(
            terminalID: terminalID,
            state: .completed,
            event: "Stop"
        )
        store.statusesByDirectoryURL = [statusDirectoryURL: [terminalID: status]]

        await state.refreshAgentStatuses()
        await state.refreshAgentStatuses()
        try await waitForNotificationDelivery()

        XCTAssertEqual(notifier.notifiedStatuses.map(\.state), [.completed])
    }

    func testDoesNotNotifyRunningCodingAgentStatus() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier)
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )
        let terminalID = try XCTUnwrap(state.tabs.first?.id)
        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                terminalID: makeStatus(
                    terminalID: terminalID,
                    state: .running,
                    event: "PreToolUse"
                )
            ]
        ]

        await state.refreshAgentStatuses()
        try await waitForNotificationDelivery()

        XCTAssertTrue(notifier.notifiedStatuses.isEmpty)
    }

    func testNotifiesEachEligibleCodingAgentStateChange() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier)
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )
        let terminalID = try XCTUnwrap(state.tabs.first?.id)

        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                terminalID: makeStatus(
                    terminalID: terminalID,
                    state: .waiting,
                    event: "PermissionRequest",
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
                )
            ]
        ]
        await state.refreshAgentStatuses()

        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                terminalID: makeStatus(
                    terminalID: terminalID,
                    state: .error,
                    event: "StopFailure",
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_001)
                )
            ]
        ]
        await state.refreshAgentStatuses()
        try await waitForNotificationDelivery()

        XCTAssertEqual(notifier.notifiedStatuses.map(\.state), [.waiting, .error])
        XCTAssertEqual(notifier.notifiedStatuses.map(\.event), ["PermissionRequest", "StopFailure"])
    }

    func testCanRevealTerminalForNotification() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier)
        let rootURL = URL(filePath: "/tmp/Project")

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: nil
        )
        let terminalID = try XCTUnwrap(state.tabs.first?.id)

        XCTAssertEqual(state.workspaceID(containing: terminalID), rootURL.standardizedFileURL)

        state.revealTab(terminalID, in: rootURL.standardizedFileURL)

        XCTAssertEqual(state.activeWorkspaceURL, rootURL.standardizedFileURL)
        XCTAssertEqual(state.selectedTabID, terminalID)
    }

    private func makeTerminalState(
        store: FakeCodingAgentStatusStore,
        notifier: RecordingCodingAgentStatusNotifier
    ) -> TerminalState {
        TerminalState(
            shellResolver: TerminalShellResolver(environment: [:], fallbackShellPath: "/bin/zsh"),
            agentStatusStore: store,
            agentStatusNotifier: notifier
        )
    }

    private func makeStatus(
        terminalID: TerminalTab.ID,
        provider: CodingAgentProvider = .codex,
        state: CodingAgentState,
        event: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> CodingAgentStatus {
        CodingAgentStatus(
            terminalID: terminalID,
            provider: provider,
            state: state,
            event: event,
            updatedAt: updatedAt,
            workspaceRoot: URL(filePath: "/tmp/Project")
        )
    }

    private func waitForNotificationDelivery() async throws {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

private final class FakeCodingAgentStatusStore: CodingAgentStatusStoring, @unchecked Sendable {
    var statusesByDirectoryURL: [URL: [TerminalTab.ID: CodingAgentStatus]] = [:]

    func load(
        from statusDirectoryURL: URL?,
        openTerminalIDs: Set<TerminalTab.ID>
    ) async -> [TerminalTab.ID: CodingAgentStatus] {
        guard let statusDirectoryURL else { return [:] }

        let statuses = statusesByDirectoryURL[statusDirectoryURL.standardizedFileURL]
            ?? statusesByDirectoryURL[statusDirectoryURL]
            ?? [:]

        return statuses
            .filter { terminalID, _ in openTerminalIDs.contains(terminalID) }
    }
}

private final class RecordingCodingAgentStatusNotifier: CodingAgentStatusNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CodingAgentStatus] = []
    private var contexts: [CodingAgentNotificationContext] = []

    var notifiedStatuses: [CodingAgentStatus] {
        lock.withLock {
            statuses
        }
    }

    var notifiedContexts: [CodingAgentNotificationContext] {
        lock.withLock {
            contexts
        }
    }

    func notify(status: CodingAgentStatus, context: CodingAgentNotificationContext) async {
        lock.withLock {
            statuses.append(status)
            contexts.append(context)
        }
    }
}
