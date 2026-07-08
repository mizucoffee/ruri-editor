//
//  TerminalViewModelMinimizeTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

@MainActor
final class TerminalViewModelMinimizeTests: XCTestCase {
    func testSetMinimizedWithoutActiveWorkspaceIsNoOp() {
        let state = makeTerminalState()

        state.setMinimized(true)

        XCTAssertFalse(state.isMinimized)
    }

    func testSetMinimizedUpdatesStateWithActiveWorkspace() async {
        let state = makeTerminalState()
        let rootURL = URL(filePath: "/tmp/Project")
        let statusDirectoryURL = rootURL.appending(path: ".ruri/agent-status", directoryHint: .isDirectory)
        state.updateActiveWorkspace(
            id: rootURL,
            rootURL: rootURL,
            agentStatusDirectoryURL: statusDirectoryURL
        )

        state.setMinimized(true)
        XCTAssertTrue(state.isMinimized)

        state.setMinimized(true)
        XCTAssertTrue(state.isMinimized)

        state.toggleMinimized()
        XCTAssertFalse(state.isMinimized)
    }

    private func makeTerminalState() -> TerminalViewModel {
        TerminalViewModel(
            shellResolver: TerminalShellResolver(environment: [:], fallbackShellPath: "/bin/zsh"),
            agentStatusStore: EmptyCodingAgentStatusStore(),
            agentStatusNotifier: NoopCodingAgentStatusNotifier(),
            isApplicationActive: { false }
        )
    }
}

private final class EmptyCodingAgentStatusStore: CodingAgentStatusStoring, @unchecked Sendable {
    func load(
        from statusDirectoryURL: URL?,
        openTerminalIDs: Set<TerminalTab.ID>
    ) async -> [TerminalTab.ID: CodingAgentStatus] {
        [:]
    }
}

private final class NoopCodingAgentStatusNotifier: CodingAgentStatusNotifying, @unchecked Sendable {
    func notify(status: CodingAgentStatus, context: CodingAgentNotificationContext) async {}

    func removeDeliveredNotifications(forTerminalIDs terminalIDs: Set<TerminalTab.ID>) async {}
}
