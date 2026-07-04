//
//  TerminalWorkspaceStateTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class TerminalWorkspaceStateTests: XCTestCase {
    func testCreateTabUsesWorkspaceRootAndSelectsNewTab() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)

        let tab = workspace.createTab(shellPath: "/bin/zsh")

        XCTAssertEqual(tab.cwd, rootURL.standardizedFileURL)
        XCTAssertEqual(tab.shellPath, "/bin/zsh")
        XCTAssertEqual(workspace.tabs.map(\.id), [tab.id])
        XCTAssertEqual(workspace.selectedTabID, tab.id)
    }

    func testSnapshotIncludesWorkspaceRootTabsAndSelection() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)

        let first = workspace.createTab(shellPath: "/bin/zsh")
        let second = workspace.createTab(shellPath: "/bin/zsh")
        workspace.selectTab(first.id)

        let snapshot = workspace.snapshot

        XCTAssertEqual(snapshot.id, rootURL.standardizedFileURL)
        XCTAssertEqual(snapshot.rootURL, rootURL.standardizedFileURL)
        XCTAssertEqual(snapshot.tabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(snapshot.selectedTabID, first.id)
    }

    func testSelectTabAtShortcutNumberUsesOneBasedTabOrder() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let first = workspace.createTab(shellPath: "/bin/zsh")
        let second = workspace.createTab(shellPath: "/bin/zsh")
        let third = workspace.createTab(shellPath: "/bin/zsh")

        workspace.selectTab(atShortcutNumber: 1)
        XCTAssertEqual(workspace.selectedTabID, first.id)

        workspace.selectTab(atShortcutNumber: 2)
        XCTAssertEqual(workspace.selectedTabID, second.id)

        workspace.selectTab(atShortcutNumber: 3)
        XCTAssertEqual(workspace.selectedTabID, third.id)
    }

    func testSelectTabAtShortcutNumberZeroSelectsLastTab() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        _ = workspace.createTab(shellPath: "/bin/zsh")
        let second = workspace.createTab(shellPath: "/bin/zsh")
        workspace.selectTab(atShortcutNumber: 1)

        workspace.selectTab(atShortcutNumber: 0)

        XCTAssertEqual(workspace.selectedTabID, second.id)
    }

    func testSelectTabAtShortcutNumberOutOfRangeDoesNothing() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let tab = workspace.createTab(shellPath: "/bin/zsh")

        workspace.selectTab(atShortcutNumber: 2)

        XCTAssertEqual(workspace.selectedTabID, tab.id)
    }

    func testSnapshotAttachesCodingAgentStatusAndUnreadFlag() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let tab = workspace.createTab(shellPath: "/bin/zsh")
        let status = CodingAgentStatus(
            terminalID: tab.id,
            provider: .claude,
            state: .waiting,
            event: "PermissionRequest",
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            workspaceRoot: rootURL
        )

        let snapshot = workspace.snapshot(
            agentStatusesByTabID: [tab.id: status],
            unreadStatusKeysByTabID: [tab.id: status.changeKey]
        )

        XCTAssertEqual(snapshot.tabs.first?.agentStatus?.status, status)
        XCTAssertEqual(snapshot.tabs.first?.agentStatus?.isUnread, true)
    }

    func testTabsAreIndependentPerWorkspace() {
        let firstRootURL = URL(filePath: "/tmp/First")
        let secondRootURL = URL(filePath: "/tmp/Second")
        var first = TerminalWorkspaceState(id: firstRootURL, rootURL: firstRootURL)
        var second = TerminalWorkspaceState(id: secondRootURL, rootURL: secondRootURL)

        let firstTab = first.createTab(shellPath: "/bin/zsh")
        let secondTab = second.createTab(shellPath: "/bin/zsh")
        _ = second.createTab(shellPath: "/bin/zsh")

        XCTAssertEqual(first.tabs.map(\.id), [firstTab.id])
        XCTAssertEqual(first.selectedTabID, firstTab.id)
        XCTAssertEqual(second.tabs.count, 2)
        XCTAssertEqual(second.tabs.first?.id, secondTab.id)
        XCTAssertNotEqual(first.selectedTabID, second.selectedTabID)
    }

    func testCloseRunningTabRequiresConfirmation() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let tab = workspace.createTab(shellPath: "/bin/zsh")

        let decision = workspace.requestCloseTab(tab.id)

        XCTAssertEqual(decision, .needsConfirmation(tab))
        XCTAssertEqual(workspace.pendingCloseTabID, tab.id)
        XCTAssertEqual(workspace.tabs.map(\.id), [tab.id])
    }

    func testConfirmPendingCloseRemovesTabAndRepairsSelection() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let first = workspace.createTab(shellPath: "/bin/zsh")
        let second = workspace.createTab(shellPath: "/bin/zsh")
        workspace.selectTab(first.id)

        _ = workspace.requestCloseTab(first.id)
        let closed = workspace.confirmPendingClose()

        XCTAssertEqual(closed?.id, first.id)
        XCTAssertEqual(workspace.tabs.map(\.id), [second.id])
        XCTAssertEqual(workspace.selectedTabID, second.id)
        XCTAssertNil(workspace.pendingCloseTabID)
    }

    func testCloseTerminatedTabRemovesTabAndRepairsSelection() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let first = workspace.createTab(shellPath: "/bin/zsh")
        let second = workspace.createTab(shellPath: "/bin/zsh")
        workspace.selectTab(first.id)

        let closed = workspace.closeTerminatedTab(first.id, exitCode: 0)

        XCTAssertEqual(closed?.id, first.id)
        XCTAssertEqual(workspace.tabs.map(\.id), [second.id])
        XCTAssertEqual(workspace.selectedTabID, second.id)
        XCTAssertNil(workspace.pendingCloseTabID)
    }

    func testCreateRunTabUsesWorkspaceRootAndSelectsRunTab() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let configuration = RunConfiguration(name: "Test", command: "swift test")

        let result = workspace.createRunTab(configuration: configuration, shellPath: "/bin/zsh")

        XCTAssertNil(result.closedTab)
        XCTAssertEqual(result.runTab.cwd, rootURL.standardizedFileURL)
        XCTAssertEqual(result.runTab.shellPath, "/bin/zsh")
        XCTAssertEqual(result.runTab.launchArguments, ["-lc", "swift test"])
        XCTAssertEqual(result.runTab.kind, .run(configurationID: configuration.id))
        XCTAssertEqual(workspace.selectedTabID, result.runTab.id)
    }

    func testCreateRunTabReplacesExistingRunTabInSameWorkspace() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let firstConfiguration = RunConfiguration(name: "First", command: "echo first")
        let secondConfiguration = RunConfiguration(name: "Second", command: "echo second")

        let first = workspace.createRunTab(configuration: firstConfiguration, shellPath: "/bin/zsh")
        let second = workspace.createRunTab(configuration: secondConfiguration, shellPath: "/bin/zsh")

        XCTAssertEqual(second.closedTab?.id, first.runTab.id)
        XCTAssertEqual(workspace.tabs.map(\.id), [second.runTab.id])
        XCTAssertEqual(workspace.selectedTabID, second.runTab.id)
    }

    func testRunTabClosesWhenProcessTerminates() {
        let rootURL = URL(filePath: "/tmp/Project")
        var workspace = TerminalWorkspaceState(id: rootURL, rootURL: rootURL)
        let configuration = RunConfiguration(name: "Test", command: "swift test")
        let result = workspace.createRunTab(configuration: configuration, shellPath: "/bin/zsh")

        let closed = workspace.closeTerminatedTab(result.runTab.id, exitCode: 2)

        XCTAssertEqual(closed?.id, result.runTab.id)
        XCTAssertTrue(workspace.tabs.isEmpty)
        XCTAssertNil(workspace.selectedTabID)
    }

    func testShellResolverPrefersShellEnvironment() {
        let resolver = TerminalShellResolver(environment: ["SHELL": "/bin/fish"])

        XCTAssertEqual(resolver.shellPath(), "/bin/fish")
    }

    func testShellResolverFallsBackToZsh() {
        let resolver = TerminalShellResolver(environment: [:])

        XCTAssertEqual(resolver.shellPath(), "/bin/zsh")
    }

    func testShellLaunchConfigurationUsesLoginShellExecName() {
        let configuration = TerminalShellLaunchConfiguration(shellPath: "/bin/zsh")

        XCTAssertEqual(configuration.executable, "/bin/zsh")
        XCTAssertEqual(configuration.execName, "-zsh")
        XCTAssertEqual(configuration.arguments, [])
    }

    func testShellLaunchConfigurationUsesLoginShellExecNameForOtherShells() {
        let configuration = TerminalShellLaunchConfiguration(shellPath: "/opt/homebrew/bin/fish")

        XCTAssertEqual(configuration.executable, "/opt/homebrew/bin/fish")
        XCTAssertEqual(configuration.execName, "-fish")
        XCTAssertEqual(configuration.arguments, [])
    }
}
