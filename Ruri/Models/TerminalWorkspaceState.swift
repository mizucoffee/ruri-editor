//
//  TerminalWorkspaceState.swift
//  ruri
//

import Foundation

enum TerminalCloseDecision: Equatable {
    case closed(TerminalTab)
    case needsConfirmation(TerminalTab)
}

struct TerminalWorkspaceState {
    let id: ProjectWorkspaceSnapshot.ID
    let rootURL: URL

    private(set) var tabs: [TerminalTab] = []
    private(set) var selectedTabID: TerminalTab.ID?
    private(set) var pendingCloseTabID: TerminalTab.ID?

    private var nextTabNumber = 1

    init(id: ProjectWorkspaceSnapshot.ID, rootURL: URL) {
        self.id = id
        self.rootURL = rootURL.standardizedFileURL
    }

    var snapshots: [TerminalTabSnapshot] {
        snapshots(agentStatusesByTabID: [:], unreadStatusKeysByTabID: [:])
    }

    var snapshot: TerminalWorkspaceSnapshot {
        snapshot(agentStatusesByTabID: [:], unreadStatusKeysByTabID: [:])
    }

    func snapshots(
        agentStatusesByTabID: [TerminalTab.ID: CodingAgentStatus],
        unreadStatusKeysByTabID: [TerminalTab.ID: String]
    ) -> [TerminalTabSnapshot] {
        tabs.map { tab in
            let agentStatus = agentStatusesByTabID[tab.id].map { status in
                CodingAgentTerminalStatus(
                    status: status,
                    isUnread: unreadStatusKeysByTabID[tab.id] == status.changeKey
                )
            }

            return tab.snapshot(agentStatus: agentStatus)
        }
    }

    func snapshot(
        agentStatusesByTabID: [TerminalTab.ID: CodingAgentStatus],
        unreadStatusKeysByTabID: [TerminalTab.ID: String]
    ) -> TerminalWorkspaceSnapshot {
        TerminalWorkspaceSnapshot(
            id: id,
            rootURL: rootURL,
            tabs: snapshots(
                agentStatusesByTabID: agentStatusesByTabID,
                unreadStatusKeysByTabID: unreadStatusKeysByTabID
            ),
            selectedTabID: selectedTabID
        )
    }

    var selectedTab: TerminalTab? {
        guard let selectedTabID else { return nil }
        return tab(for: selectedTabID)
    }

    func tab(for id: TerminalTab.ID) -> TerminalTab? {
        tabs.first { $0.id == id }
    }

    mutating func createTab(shellPath: String) -> TerminalTab {
        let title = "Terminal \(nextTabNumber)"
        nextTabNumber += 1

        let tab = TerminalTab(
            defaultTitle: title,
            cwd: rootURL,
            shellPath: shellPath
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return tab
    }

    mutating func createRunTab(
        configuration: RunConfiguration,
        shellPath: String
    ) -> (closedTab: TerminalTab?, runTab: TerminalTab) {
        let closedTab = closeExistingRunTab()
        let tab = TerminalTab(
            defaultTitle: "Run: \(configuration.name)",
            cwd: rootURL,
            shellPath: shellPath,
            launchArguments: ["-lc", configuration.command],
            kind: .run(configurationID: configuration.id)
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return (closedTab, tab)
    }

    mutating func selectTab(_ id: TerminalTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    mutating func requestCloseTab(_ id: TerminalTab.ID) -> TerminalCloseDecision? {
        guard let tab = tab(for: id) else { return nil }

        if tab.status.isRunning {
            pendingCloseTabID = id
            return .needsConfirmation(tab)
        }

        return closeTab(id).map(TerminalCloseDecision.closed)
    }

    mutating func confirmPendingClose() -> TerminalTab? {
        guard let pendingCloseTabID else { return nil }

        self.pendingCloseTabID = nil
        return closeTab(pendingCloseTabID)
    }

    mutating func cancelPendingClose() {
        pendingCloseTabID = nil
    }

    mutating func closeTerminatedTab(_ id: TerminalTab.ID, exitCode: Int32?) -> TerminalTab? {
        guard tab(for: id) != nil else { return nil }
        updateStatus(.exited(exitCode: exitCode), for: id)
        return closeTab(id)
    }

    mutating func updateTitle(_ title: String, for id: TerminalTab.ID) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }

        tabs[index].title = trimmedTitle
    }

    mutating func updateStatus(_ status: TerminalTabStatus, for id: TerminalTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].status = status
    }

    func runningRunTabID() -> TerminalTab.ID? {
        tabs.first { $0.kind.isRun && $0.status.isRunning }?.id
    }

    private mutating func closeTab(_ id: TerminalTab.ID) -> TerminalTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }

        let closedTab = tabs.remove(at: index)
        if pendingCloseTabID == id {
            pendingCloseTabID = nil
        }

        if tabs.isEmpty {
            selectedTabID = nil
        } else if selectedTabID == id || selectedTabIDNeedsRepair {
            selectTabNear(index)
        }

        return closedTab
    }

    private mutating func closeExistingRunTab() -> TerminalTab? {
        guard let id = tabs.first(where: { $0.kind.isRun })?.id else { return nil }
        return closeTab(id)
    }

    private var selectedTabIDNeedsRepair: Bool {
        guard let selectedTabID else { return false }
        return !tabs.contains { $0.id == selectedTabID }
    }

    private mutating func selectTabNear(_ index: Int) {
        let nextTab = tabs.enumerated().first { candidateIndex, _ in
            candidateIndex >= index
        }?.element ?? tabs.last

        selectedTabID = nextTab?.id
    }
}
