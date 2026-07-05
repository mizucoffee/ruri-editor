//
//  TerminalViewModelCodingAgentNotificationTests.swift
//  ruriTests
//

import AppKit
import Foundation
import XCTest
@testable import ruri

@MainActor
final class TerminalViewModelCodingAgentNotificationTests: XCTestCase {
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
        try await waitForNotificationCount(notifier, 1)

        XCTAssertEqual(notifier.notifiedStatuses.map(\.state), [.waiting])
        XCTAssertEqual(notifier.notifiedStatuses.map(\.event), ["PermissionRequest"])
        XCTAssertEqual(notifier.notifiedContexts.map(\.terminalTitle), ["Terminal 1"])
        XCTAssertEqual(notifier.notifiedContexts.map(\.workspaceName), ["Project"])
    }

    func testNotifiesCompletedCodingAgentStatusOnce() async throws {
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
        try await waitForNotificationCount(notifier, 1)

        XCTAssertEqual(notifier.notifiedStatuses.map(\.state), [.completed])
        XCTAssertEqual(notifier.notifiedStatuses.map(\.event), ["Stop"])
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
        try await waitForNotificationQuiescence()

        XCTAssertTrue(notifier.notifiedStatuses.isEmpty)
    }

    func testDoesNotNotifyCodingAgentErrorStatus() async throws {
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
                    state: .error,
                    event: "StopFailure",
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_001)
                )
            ]
        ]
        await state.refreshAgentStatuses()
        try await waitForNotificationQuiescence()

        XCTAssertTrue(notifier.notifiedStatuses.isEmpty)
    }

    func testNotifiesVisibleSelectedTerminalWhileApplicationActive() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier, isApplicationActive: { true })
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
        try await waitForNotificationCount(notifier, 1)

        XCTAssertEqual(notifier.notifiedStatuses.map(\.state), [.waiting])
        // 出した直後の既読処理で通知が取り下げられない(表示前に消えない)こと。
        try await waitForNotificationQuiescence()
        XCTAssertTrue(notifier.removedTerminalIDBatches.isEmpty)
    }

    func testKeepsDeliveredNotificationAcrossRefreshesUntilVisibleTerminalReselected() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier, isApplicationActive: { true })
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
        try await waitForNotificationCount(notifier, 1)

        // refreshはユーザー操作ではないので、表示中でも配信済み通知を取り下げない。
        await state.refreshAgentStatuses()
        try await waitForNotificationQuiescence()
        XCTAssertTrue(notifier.removedTerminalIDBatches.isEmpty)

        state.selectTab(terminalID)

        try await TestSupport.waitUntil("delivered notification removal") {
            notifier.removedTerminalIDBatches.contains([terminalID])
        }
    }

    func testRemovesDeliveredNotificationWhenNotifiedTerminalBecomesVisible() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        var isApplicationActive = false
        let state = makeTerminalState(store: store, notifier: notifier, isApplicationActive: { isApplicationActive })
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )
        let firstTerminalID = try XCTUnwrap(state.tabs.first?.id)
        state.createTab()
        XCTAssertNotEqual(state.selectedTabID, firstTerminalID)
        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                firstTerminalID: makeStatus(
                    terminalID: firstTerminalID,
                    state: .waiting,
                    event: "PermissionRequest"
                )
            ]
        ]

        await state.refreshAgentStatuses()
        try await waitForNotificationCount(notifier, 1)
        XCTAssertTrue(notifier.removedTerminalIDBatches.isEmpty)

        isApplicationActive = true
        state.selectTab(firstTerminalID)

        try await TestSupport.waitUntil("delivered notification removal") {
            notifier.removedTerminalIDBatches.contains([firstTerminalID])
        }
    }

    func testRemovesDeliveredNotificationOnVisibleTerminalUserInteraction() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier, isApplicationActive: { true })
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
        try await waitForNotificationCount(notifier, 1)
        XCTAssertTrue(notifier.removedTerminalIDBatches.isEmpty)

        state.markTerminalSeenByUserInteraction(terminalID)

        try await TestSupport.waitUntil("delivered notification removal") {
            notifier.removedTerminalIDBatches.contains([terminalID])
        }
    }

    func testDoesNotRemoveDeliveredNotificationOnHiddenTerminalUserInteraction() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        let state = makeTerminalState(store: store, notifier: notifier, isApplicationActive: { true })
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)

        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )
        let firstTerminalID = try XCTUnwrap(state.tabs.first?.id)
        state.createTab()
        XCTAssertNotEqual(state.selectedTabID, firstTerminalID)
        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                firstTerminalID: makeStatus(
                    terminalID: firstTerminalID,
                    state: .waiting,
                    event: "PermissionRequest"
                )
            ]
        ]

        await state.refreshAgentStatuses()
        try await waitForNotificationCount(notifier, 1)

        // 選択中でないターミナルへの操作扱いでは取り下げない。
        state.markTerminalSeenByUserInteraction(firstTerminalID)

        try await waitForNotificationQuiescence()
        XCTAssertTrue(notifier.removedTerminalIDBatches.isEmpty)
    }

    func testRemovesDeliveredNotificationOnApplicationActivation() async throws {
        let store = FakeCodingAgentStatusStore()
        let notifier = RecordingCodingAgentStatusNotifier()
        var isApplicationActive = false
        let state = makeTerminalState(store: store, notifier: notifier, isApplicationActive: { isApplicationActive })
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
                    state: .completed,
                    event: "Stop"
                )
            ]
        ]

        await state.refreshAgentStatuses()
        try await waitForNotificationCount(notifier, 1)
        XCTAssertTrue(notifier.removedTerminalIDBatches.isEmpty)

        isApplicationActive = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        try await TestSupport.waitUntil("delivered notification removal") {
            notifier.removedTerminalIDBatches.contains([terminalID])
        }
    }

    func testRemovesDeliveredNotificationWhenAgentResumesRunning() async throws {
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
        try await waitForNotificationCount(notifier, 1)

        store.statusesByDirectoryURL = [
            statusDirectoryURL: [
                terminalID: makeStatus(
                    terminalID: terminalID,
                    state: .running,
                    event: "PreToolUse",
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_001)
                )
            ]
        ]
        await state.refreshAgentStatuses()

        try await TestSupport.waitUntil("delivered notification removal") {
            notifier.removedTerminalIDBatches.contains([terminalID])
        }
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
        notifier: RecordingCodingAgentStatusNotifier,
        isApplicationActive: @escaping () -> Bool = { false }
    ) -> TerminalViewModel {
        TerminalViewModel(
            shellResolver: TerminalShellResolver(environment: [:], fallbackShellPath: "/bin/zsh"),
            agentStatusStore: store,
            agentStatusNotifier: notifier,
            isApplicationActive: isApplicationActive
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

    private func waitForNotificationCount(
        _ notifier: RecordingCodingAgentStatusNotifier,
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await TestSupport.waitUntil("notification delivery", file: file, line: line) {
            notifier.notifiedStatuses.count >= expectedCount
        }
    }

    // 「通知されないこと」を検証する否定アサーション用。完了通知が存在しないため短い固定待ちを使う。
    private func waitForNotificationQuiescence() async throws {
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
    private var removedIDs: [Set<TerminalTab.ID>] = []

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

    var removedTerminalIDBatches: [Set<TerminalTab.ID>] {
        lock.withLock {
            removedIDs
        }
    }

    func notify(status: CodingAgentStatus, context: CodingAgentNotificationContext) async {
        lock.withLock {
            statuses.append(status)
            contexts.append(context)
        }
    }

    func removeDeliveredNotifications(forTerminalIDs terminalIDs: Set<TerminalTab.ID>) async {
        lock.withLock {
            removedIDs.append(terminalIDs)
        }
    }
}
