//
//  TerminalState.swift
//  ruri
//

import AppKit
import Combine
import Foundation

@MainActor
final class TerminalState: ObservableObject, TerminalRuntimeDelegate {
    @Published private(set) var activeWorkspaceURL: URL?
    @Published private(set) var tabs: [TerminalTabSnapshot] = []
    @Published private(set) var selectedTabID: TerminalTab.ID?
    @Published private(set) var workspaceSnapshots: [TerminalWorkspaceSnapshot] = []
    @Published private(set) var isMinimized = false
    @Published private(set) var focusRequest: TerminalFocusRequest?
    @Published private(set) var closeConfirmation: TerminalCloseConfirmation?

    private var activeWorkspaceID: ProjectWorkspaceSnapshot.ID?
    private var workspaces: [ProjectWorkspaceSnapshot.ID: TerminalWorkspaceState] = [:]
    private var runtimesByTabID: [TerminalTab.ID: TerminalRuntime] = [:]
    private var agentStatusDirectoryURLsByWorkspaceID: [ProjectWorkspaceSnapshot.ID: URL] = [:]
    private var agentStatusesByTabID: [TerminalTab.ID: CodingAgentStatus] = [:]
    private var unreadAgentStatusKeysByTabID: [TerminalTab.ID: String] = [:]
    private lazy var agentStatusWatcher = CodingAgentStatusWatcher { [weak self] _ in
        Task { @MainActor in
            await self?.refreshAgentStatuses()
        }
    }
    private let shellResolver: TerminalShellResolver
    private let agentStatusStore: any CodingAgentStatusStoring
    private let agentStatusNotifier: any CodingAgentStatusNotifying

    init(
        shellResolver: TerminalShellResolver? = nil,
        agentStatusStore: any CodingAgentStatusStoring = CodingAgentStatusStore(),
        agentStatusNotifier: any CodingAgentStatusNotifying = CodingAgentStatusNotifier()
    ) {
        self.shellResolver = shellResolver ?? TerminalShellResolver()
        self.agentStatusStore = agentStatusStore
        self.agentStatusNotifier = agentStatusNotifier
    }

    deinit {
        MainActor.assumeIsolated {
            agentStatusWatcher.stopWatchingAll()
            runtimesByTabID.values.forEach { $0.invalidate() }
        }
    }

    var hasActiveWorkspace: Bool {
        activeWorkspaceID != nil
    }

    var canStopRunInActiveWorkspace: Bool {
        guard let activeWorkspaceID,
              let workspace = workspaces[activeWorkspaceID] else {
            return false
        }

        guard let runTabID = workspace.runningRunTabID(),
              let runtime = runtimesByTabID[runTabID] else {
            return false
        }

        return runtime.isRunning
    }

    var selectedTab: TerminalTabSnapshot? {
        guard let selectedTabID else { return nil }
        return tabs.first { $0.id == selectedTabID }
    }

    var closeConfirmationMessage: String? {
        guard let closeConfirmation else { return nil }
        return "Terminate \(closeConfirmation.title)?"
    }

    func updateActiveWorkspace(
        id: ProjectWorkspaceSnapshot.ID?,
        rootURL: URL?,
        agentStatusDirectoryURL: URL?
    ) {
        if activeWorkspaceID != id {
            cancelPendingCloseInActiveWorkspace()
            closeConfirmation = nil
        }

        activeWorkspaceID = id

        guard let id,
              let rootURL else {
            activeWorkspaceURL = nil
            tabs = []
            selectedTabID = nil
            closeConfirmation = nil
            agentStatusDirectoryURLsByWorkspaceID = [:]
            agentStatusesByTabID = [:]
            unreadAgentStatusKeysByTabID = [:]
            updateAgentStatusWatches()
            publishWorkspaceSnapshots()
            return
        }

        if let agentStatusDirectoryURL {
            agentStatusDirectoryURLsByWorkspaceID[id] = agentStatusDirectoryURL.standardizedFileURL
        } else {
            agentStatusDirectoryURLsByWorkspaceID.removeValue(forKey: id)
        }

        if workspaces[id] == nil {
            var workspace = TerminalWorkspaceState(id: id, rootURL: rootURL)
            let initialTab = workspace.createTab(shellPath: shellResolver.shellPath())
            workspaces[id] = workspace
            _ = ensureRuntime(for: initialTab.snapshot(), workspaceID: id)
        }

        updateAgentStatusWatches()
        scheduleAgentStatusRefresh()
        markVisibleSelectedTerminalSeen()
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func toggleMinimized() {
        guard hasActiveWorkspace else { return }
        isMinimized.toggle()
        markVisibleSelectedTerminalSeen()
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func createTab() {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID] else {
            return
        }

        let tab = workspace.createTab(shellPath: shellResolver.shellPath())
        workspaces[activeWorkspaceID] = workspace
        _ = ensureRuntime(for: tab.snapshot(), workspaceID: activeWorkspaceID)
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func run(_ configuration: RunConfiguration) {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID] else {
            return
        }

        let result = workspace.createRunTab(
            configuration: configuration,
            shellPath: shellResolver.shellPath()
        )
        workspaces[activeWorkspaceID] = workspace
        if let closedTab = result.closedTab {
            closeRuntime(for: closedTab.id)
        }
        _ = ensureRuntime(for: result.runTab.snapshot(), workspaceID: activeWorkspaceID)
        isMinimized = false
        focusRequest = TerminalFocusRequest(tabID: result.runTab.id)
        markVisibleSelectedTerminalSeen()
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func stopRunInActiveWorkspace() {
        guard let activeWorkspaceID,
              let workspace = workspaces[activeWorkspaceID],
              let runTabID = workspace.runningRunTabID() else {
            return
        }

        runtimesByTabID[runTabID]?.terminate()
    }

    func selectTab(_ id: TerminalTab.ID) {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID] else {
            return
        }

        workspace.selectTab(id)
        workspaces[activeWorkspaceID] = workspace
        markVisibleSelectedTerminalSeen()
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func revealTab(
        _ tabID: TerminalTab.ID,
        in workspaceID: ProjectWorkspaceSnapshot.ID,
        requestsFocus: Bool = false
    ) {
        guard var workspace = workspaces[workspaceID],
              workspace.tab(for: tabID) != nil else {
            return
        }

        if activeWorkspaceID != workspaceID {
            cancelPendingCloseInActiveWorkspace()
            closeConfirmation = nil
        }

        activeWorkspaceID = workspaceID
        workspace.selectTab(tabID)
        workspaces[workspaceID] = workspace
        isMinimized = false
        if requestsFocus {
            focusRequest = TerminalFocusRequest(tabID: tabID)
        }

        markVisibleSelectedTerminalSeen()
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func removeWorkspace(id: ProjectWorkspaceSnapshot.ID) {
        let wasActiveWorkspace = activeWorkspaceID == id
        guard let workspace = workspaces.removeValue(forKey: id) else {
            if wasActiveWorkspace {
                activeWorkspaceID = nil
                closeConfirmation = nil
                publishActiveWorkspace()
            }
            publishWorkspaceSnapshots()
            return
        }

        for tab in workspace.tabs {
            closeRuntime(for: tab.id)
            agentStatusesByTabID.removeValue(forKey: tab.id)
            unreadAgentStatusKeysByTabID.removeValue(forKey: tab.id)
        }
        agentStatusDirectoryURLsByWorkspaceID.removeValue(forKey: id)

        if wasActiveWorkspace {
            activeWorkspaceID = nil
            closeConfirmation = nil
            publishActiveWorkspace()
        }
        updateAgentStatusWatches()
        publishWorkspaceSnapshots()
    }

    func requestCloseTab(_ id: TerminalTab.ID) {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID],
              let decision = workspace.requestCloseTab(id) else {
            return
        }

        workspaces[activeWorkspaceID] = workspace

        switch decision {
        case .closed(let tab):
            closeRuntime(for: tab.id)
            agentStatusesByTabID.removeValue(forKey: tab.id)
            unreadAgentStatusKeysByTabID.removeValue(forKey: tab.id)
            closeConfirmation = nil
            publishActiveWorkspace()
            publishWorkspaceSnapshots()

        case .needsConfirmation(let tab):
            closeConfirmation = TerminalCloseConfirmation(tabID: tab.id, title: tab.snapshot().title)
            publishActiveWorkspace()
            publishWorkspaceSnapshots()
        }
    }

    func confirmCloseTerminalTab() {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID],
              let closedTab = workspace.confirmPendingClose() else {
            closeConfirmation = nil
            return
        }

        workspaces[activeWorkspaceID] = workspace
        closeRuntime(for: closedTab.id)
        agentStatusesByTabID.removeValue(forKey: closedTab.id)
        unreadAgentStatusKeysByTabID.removeValue(forKey: closedTab.id)
        closeConfirmation = nil
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func cancelCloseTerminalTab() {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID] else {
            closeConfirmation = nil
            return
        }

        workspace.cancelPendingClose()
        workspaces[activeWorkspaceID] = workspace
        closeConfirmation = nil
        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    func terminalView(for id: TerminalTab.ID) -> NSView? {
        guard let activeWorkspaceID,
              let workspace = workspaces[activeWorkspaceID],
              let tab = workspace.tab(for: id) else {
            return nil
        }

        return ensureRuntime(for: tab.snapshot(), workspaceID: activeWorkspaceID).terminalView
    }

    func terminalRuntime(_ runtime: TerminalRuntime, didUpdateTitle title: String) {
        guard var workspace = workspaces[runtime.workspaceID] else { return }

        workspace.updateTitle(title, for: runtime.tabID)
        workspaces[runtime.workspaceID] = workspace

        if activeWorkspaceID == runtime.workspaceID {
            publishActiveWorkspace()
        }
        publishWorkspaceSnapshots()
    }

    func terminalRuntime(_ runtime: TerminalRuntime, didTerminateWithExitCode exitCode: Int32?) {
        guard var workspace = workspaces[runtime.workspaceID],
              let closedTab = workspace.closeTerminatedTab(runtime.tabID, exitCode: exitCode) else {
            return
        }

        workspaces[runtime.workspaceID] = workspace
        closeRuntime(for: closedTab.id)
        agentStatusesByTabID.removeValue(forKey: closedTab.id)
        unreadAgentStatusKeysByTabID.removeValue(forKey: closedTab.id)
        if closeConfirmation?.tabID == closedTab.id {
            closeConfirmation = nil
        }

        if activeWorkspaceID == runtime.workspaceID {
            publishActiveWorkspace()
        }
        publishWorkspaceSnapshots()
    }

    private func ensureRuntime(
        for tab: TerminalTabSnapshot,
        workspaceID: ProjectWorkspaceSnapshot.ID
    ) -> TerminalRuntime {
        if let runtime = runtimesByTabID[tab.id] {
            return runtime
        }

        let runtime = TerminalRuntime(
            workspaceID: workspaceID,
            tab: tab,
            agentStatusDirectoryURL: agentStatusDirectoryURLsByWorkspaceID[workspaceID]
        )
        runtime.delegate = self
        runtimesByTabID[tab.id] = runtime
        return runtime
    }

    private func closeRuntime(for id: TerminalTab.ID) {
        runtimesByTabID.removeValue(forKey: id)?.invalidate()
    }

    private func cancelPendingCloseInActiveWorkspace() {
        guard let activeWorkspaceID,
              var workspace = workspaces[activeWorkspaceID] else {
            return
        }

        workspace.cancelPendingClose()
        workspaces[activeWorkspaceID] = workspace
    }

    private func publishActiveWorkspace() {
        guard let activeWorkspaceID,
              let workspace = workspaces[activeWorkspaceID] else {
            activeWorkspaceURL = nil
            tabs = []
            selectedTabID = nil
            return
        }

        activeWorkspaceURL = workspace.rootURL
        tabs = workspace.snapshots(
            agentStatusesByTabID: agentStatusesByTabID,
            unreadStatusKeysByTabID: unreadAgentStatusKeysByTabID
        )
        selectedTabID = workspace.selectedTabID
    }

    private func publishWorkspaceSnapshots() {
        workspaceSnapshots = workspaces.values
            .map { workspace in
                workspace.snapshot(
                    agentStatusesByTabID: agentStatusesByTabID,
                    unreadStatusKeysByTabID: unreadAgentStatusKeysByTabID
                )
            }
            .sorted { first, second in
                first.displayPath.localizedStandardCompare(second.displayPath) == .orderedAscending
            }
    }

    private func updateAgentStatusWatches() {
        agentStatusWatcher.updateWatchedDirectories(Set(agentStatusDirectoryURLsByWorkspaceID.values))
    }

    private func scheduleAgentStatusRefresh() {
        Task { @MainActor [weak self] in
            await self?.refreshAgentStatuses()
        }
    }

    func refreshAgentStatuses() async {
        let openTerminalIDs = Set(workspaces.values.flatMap { workspace in
            workspace.tabs.map(\.id)
        })
        guard !openTerminalIDs.isEmpty else {
            guard !agentStatusesByTabID.isEmpty || !unreadAgentStatusKeysByTabID.isEmpty else {
                return
            }
            agentStatusesByTabID = [:]
            unreadAgentStatusKeysByTabID = [:]
            publishActiveWorkspace()
            publishWorkspaceSnapshots()
            return
        }

        let previousStatuses = agentStatusesByTabID
        let previousUnreadStatusKeys = unreadAgentStatusKeysByTabID
        var refreshedStatuses: [TerminalTab.ID: CodingAgentStatus] = [:]
        for statusDirectoryURL in Set(agentStatusDirectoryURLsByWorkspaceID.values) {
            let statuses = await agentStatusStore.load(
                from: statusDirectoryURL,
                openTerminalIDs: openTerminalIDs
            )
            for (tabID, status) in statuses {
                if let existing = refreshedStatuses[tabID],
                   existing.updatedAt >= status.updatedAt {
                    continue
                }
                refreshedStatuses[tabID] = status
            }
        }

        notifyChangedAgentStatuses(
            refreshedStatuses,
            previousStatuses: previousStatuses
        )
        updateUnreadAgentStatuses(with: refreshedStatuses, openTerminalIDs: openTerminalIDs)
        agentStatusesByTabID = refreshedStatuses
        markVisibleSelectedTerminalSeen()

        guard previousStatuses != agentStatusesByTabID ||
              previousUnreadStatusKeys != unreadAgentStatusKeysByTabID else {
            return
        }

        publishActiveWorkspace()
        publishWorkspaceSnapshots()
    }

    private func notifyChangedAgentStatuses(
        _ refreshedStatuses: [TerminalTab.ID: CodingAgentStatus],
        previousStatuses: [TerminalTab.ID: CodingAgentStatus]
    ) {
        for (tabID, status) in refreshedStatuses {
            guard status.state.isNotificationEligible,
                  previousStatuses[tabID]?.changeKey != status.changeKey else {
                continue
            }

            let context = notificationContext(for: tabID, status: status)
            Task { [agentStatusNotifier] in
                await agentStatusNotifier.notify(status: status, context: context)
            }
        }
    }

    private func notificationContext(
        for tabID: TerminalTab.ID,
        status: CodingAgentStatus
    ) -> CodingAgentNotificationContext {
        for workspace in workspaces.values {
            guard let tab = workspace.tab(for: tabID) else { continue }
            return CodingAgentNotificationContext(
                terminalTitle: tab.snapshot().title,
                workspaceName: workspace.rootURL.lastPathComponent
            )
        }

        return CodingAgentNotificationContext(
            terminalTitle: "",
            workspaceName: status.workspaceRoot?.lastPathComponent
        )
    }

    private func updateUnreadAgentStatuses(
        with refreshedStatuses: [TerminalTab.ID: CodingAgentStatus],
        openTerminalIDs: Set<TerminalTab.ID>
    ) {
        unreadAgentStatusKeysByTabID = unreadAgentStatusKeysByTabID.filter { tabID, _ in
            openTerminalIDs.contains(tabID)
        }

        for (tabID, status) in refreshedStatuses {
            guard status.state.isUnreadEligible else {
                unreadAgentStatusKeysByTabID.removeValue(forKey: tabID)
                continue
            }

            guard agentStatusesByTabID[tabID]?.changeKey != status.changeKey else {
                continue
            }

            unreadAgentStatusKeysByTabID[tabID] = status.changeKey
        }
    }

    private func markVisibleSelectedTerminalSeen() {
        guard !isMinimized,
              let activeWorkspaceID,
              let selectedTabID = workspaces[activeWorkspaceID]?.selectedTabID else {
            return
        }

        unreadAgentStatusKeysByTabID.removeValue(forKey: selectedTabID)
    }
}
