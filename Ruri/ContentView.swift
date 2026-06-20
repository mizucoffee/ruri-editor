//
//  ContentView.swift
//  ruri
//
//  Created by mizucoffee on 2026/06/08.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @ObservedObject var editor: EditorState
    @ObservedObject var editorRuntimeStore: EditorRuntimeStore
    @ObservedObject var terminalState: TerminalState
    @ObservedObject var runConfigurationState: RunConfigurationState
    @ObservedObject var textSearch: ProjectTextSearchViewModel
    @ObservedObject var tabInputSettings: EditorTabInputSettingsStore
    @ObservedObject var lineWrappingSettings: EditorLineWrappingSettingsStore
    @ObservedObject var githubAuth: GitHubAuthViewModel
    @Binding var isImporterPresented: Bool
    @Binding var isWorktreeOverviewVisible: Bool
    let openProjectInNewWindow: (URL) -> Void
    @StateObject private var fileSearch = ProjectFileSearchViewModel()
    @StateObject private var codeUsage = CodeUsageViewModel()
    @StateObject private var worktreeInitialization = WorktreeInitializationState()
    @State private var codeNavigationToast: CodeNavigationToast?
    @State private var codeNavigationToastTask: Task<Void, Never>?
    @State private var isNewWorktreeSheetPresented = false
    @State private var newWorktreeSource = NewWorktreeSource.local
    @State private var newWorktreeBranchName = ""
    @State private var newWorktreeInitializationCommand = ""
    @State private var pendingInitializationWorkspaceID: ProjectWorkspaceSnapshot.ID?
    @State private var isCreatingWorktree = false
    @State private var newWorktreeErrorMessage: String?
    @State private var remoteWorktreeBranches: [GitRemoteBranchInfo] = []
    @State private var remoteWorktreeSearchText = ""
    @State private var selectedRemoteWorktreeBranchID: GitRemoteBranchInfo.ID?
    @State private var isLoadingRemoteWorktreeBranches = false
    @State private var remoteWorktreeErrorMessage: String?
    @State private var worktreeDeletionTarget: WorktreeDeletionTarget?
    @State private var isDeletingWorktree = false

    var body: some View {
        NavigationSplitView {
            ProjectSidebarView(
                projectWorkspaces: editor.projectWorkspaces,
                activeProjectID: editor.activeProjectID,
                projectURL: editor.projectURL,
                fileTree: editor.fileTree,
                selectedFileTreeURL: editor.selectedFileTreeURL,
                gitSnapshot: editor.gitSnapshot,
                isFileTreeShowingChangedFilesOnly: editor.isFileTreeShowingChangedFilesOnly,
                canShowChangedFilesOnlyInFileTree: editor.canShowChangedFilesOnlyInFileTree,
                canFocusSelectedFileInTree: editor.canFocusSelectedFileInTree,
                selectFileTreeNode: { editor.selectFileTreeNode($0) },
                toggleFileTreeChangedFilesOnly: {
                    editor.toggleFileTreeChangedFilesOnly()
                },
                focusSelectedFileInTree: {
                    Task {
                        await editor.focusSelectedFileInTree()
                    }
                },
                openFile: { url in
                    openFile(url, activationFocusBehavior: .keepCurrentFocus)
                },
                toggleDirectory: { url in
                    Task {
                        await editor.toggleDirectory(url)
                    }
                },
                moveFileTreeSelection: { offset in
                    editor.moveFileTreeSelection(by: offset)
                },
                expandSelectedFileTreeNode: {
                    Task {
                        await editor.expandSelectedFileTreeNode()
                    }
                },
                collapseSelectedFileTreeNodeOrSelectParent: {
                    editor.collapseSelectedFileTreeNodeOrSelectParent()
                },
                activateSelectedFileTreeNode: {
                    if let selectedURL = editor.selectedFileTreeURL {
                        editorRuntimeStore.requestActivationFocusBehavior(
                            .keepCurrentFocus,
                            for: selectedURL
                        )
                    }

                    Task {
                        if let closedDocument = await editor.activateSelectedFileTreeNode() {
                            editorRuntimeStore.closeDocument(
                                workspaceID: closedDocument.workspaceID,
                                documentID: closedDocument.documentID
                            )
                        }
                    }
                },
                renameFileTreeNode: { url, newName in
                    Task {
                        await editor.renameFileTreeNode(url, to: newName)
                        fileSearch.invalidateIndex(for: editor.projectURL)
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            Color.clear.overlay {
                EditorPaneView(
                    runtimeStore: editorRuntimeStore,
                    terminalState: terminalState,
                    workspaceID: editor.activeProjectID,
                    editorMode: editor.editorMode,
                    reviewDiffState: editor.reviewDiffState,
                    reviewDiffBase: editor.reviewDiffBase,
                    reviewDiffRemoteBranches: editor.reviewDiffRemoteBranches,
                    isLoadingReviewDiffRemoteBranches: editor.isLoadingReviewDiffRemoteBranches,
                    reviewDiffRemoteBranchErrorMessage: editor.reviewDiffRemoteBranchErrorMessage,
                    reviewDiffHideWhitespace: editor.reviewDiffHideWhitespace,
                    tabs: editor.mainTabs,
                    selectedTabID: editor.selectedTabID,
                    symbolIndexStatus: editor.symbolIndexStatus,
                    fileSearchIndexStatus: fileSearch.indexStatus,
                    gitRepositoryStatus: editor.gitRepositoryStatus,
                    gitSnapshot: editor.gitSnapshot,
                    githubAuthStatus: githubAuth.status,
                    githubPullRequestStatus: editor.githubPullRequestStatus,
                    tabInputSetting: tabInputSettings.setting,
                    lineWrappingMode: lineWrappingSettings.mode,
                    editorSession: { editor.editorSession(for: $0) },
                    updateText: { editor.updateText($0, in: $1) },
                    updateSelection: { editor.updateSelection($0, in: $1) },
                    updateScrollOrigin: { editor.updateScrollOrigin($0, in: $1) },
                    requestImplementationJump: { tabID, utf16Offset in
                        resolveImplementationOrReferences(at: utf16Offset, in: tabID)
                    },
                    implementationHoverRange: { tabID, utf16Offset in
                        await editor.implementationHoverRange(at: utf16Offset, in: tabID)
                    },
                    requestReviewDiffCodeNavigation: { request in
                        resolveReviewDiffImplementationOrReferences(request)
                    },
                    reviewDiffCodeNavigationHoverRange: { request in
                        await editor.reviewDiffImplementationHoverRange(request)
                    },
                    selectTab: { editor.selectTab($0) },
                    setTabInputSetting: { tabInputSettings.setting = $0 },
                    switchGitBranch: { branchName in
                        switchGitBranch(named: branchName)
                    },
                    refreshGitHubAuthStatus: {
                        refreshGitHubAuthStatus()
                    },
                    logInToGitHub: {
                        logInToGitHub()
                    },
                    openGitHubPullRequest: { url in
                        NSWorkspace.shared.open(url)
                    },
                    selectReviewDiffBase: { base in
                        editor.setReviewDiffBase(base)
                    },
                    loadReviewDiffRemoteBranches: { refresh in
                        editor.loadReviewDiffRemoteBranches(refresh: refresh)
                    },
                    refreshReviewDiff: {
                        editor.refreshReviewDiff()
                    },
                    setReviewDiffHideWhitespace: { hideWhitespace in
                        editor.setReviewDiffHideWhitespace(hideWhitespace)
                    },
                    openReviewDiffFile: { url in
                        openFile(url, activationFocusBehavior: .focusTextView)
                    },
                    closeTab: { tabID in
                        if let closedDocument = editor.closeTab(tabID) {
                            editorRuntimeStore.closeDocument(
                                workspaceID: closedDocument.workspaceID,
                                documentID: closedDocument.documentID
                            )
                        }
                    },
                    moveTab: { editor.moveTab($0, to: $1) }
                )
            }
            .inspector(isPresented: $isWorktreeOverviewVisible) {
                WorktreeOverviewSidebarView(
                    projectWorkspaces: editor.projectWorkspaces,
                    terminalWorkspaces: terminalState.workspaceSnapshots,
                    branchStates: editor.gitBranchesByProjectID,
                    memos: editor.worktreeMemosByProjectID,
                    pullRequestStatuses: editor.githubPullRequestStatusesByProjectID,
                    pullRequestLoadingWorkspaceIDs: editor.githubPullRequestLoadingProjectIDs,
                    activeWorkspaceID: editor.activeProjectID,
                    selectedTerminalTabID: terminalState.selectedTabID,
                    deletableWorkspaceIDs: Set(editor.projectWorkspaces.compactMap { workspace in
                        editor.worktreeDeletionTarget(for: workspace.id)?.workspaceID
                    }),
                    canCreateWorktree: editor.canCreateWorktree,
                    selectProject: { workspaceID in
                        editor.selectProject(workspaceID)
                    },
                    selectTerminal: { workspaceID, tabID in
                        editor.selectProject(workspaceID)
                        terminalState.revealTab(tabID, in: workspaceID, requestsFocus: true)
                    },
                    updateMemo: { workspaceID, memo in
                        editor.setWorktreeMemo(memo, for: workspaceID)
                    },
                    createWorktree: {
                        presentNewWorktreeSheet()
                    },
                    deleteWorktree: { workspaceID in
                        presentDeleteWorktreeConfirmation(for: workspaceID)
                    },
                    pullWorktree: { workspaceID in
                        pullWorktree(workspaceID)
                    },
                    openPullRequest: { url in
                        NSWorkspace.shared.open(url)
                    }
                )
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
            }
        }
        .onAppear {
            syncTerminalWorkspace()
            fileSearch.updateActiveProject(editor.projectURL)
        }
        .task {
            await githubAuth.refresh()
        }
        .onChange(of: editor.activeProjectID) { _, _ in
            syncTerminalWorkspace()
        }
        .onChange(of: editor.projectURL) { _, _ in
            syncTerminalWorkspace()
            fileSearch.updateActiveProject(editor.projectURL)
            textSearch.updateActiveProject(editor.projectURL)
            codeUsage.dismiss()
        }
        .onChange(of: worktreeInitialization.command) { oldCommand, newCommand in
            guard isNewWorktreeSheetPresented,
                  !isCreatingWorktree,
                  pendingInitializationWorkspaceID == nil,
                  newWorktreeInitializationCommand.isEmpty || newWorktreeInitializationCommand == oldCommand else {
                return
            }

            newWorktreeInitializationCommand = newCommand
        }
        .onChange(of: editor.fileChangeNotification) { _, notification in
            guard let notification else { return }

            fileSearch.invalidateIndex(for: notification.projectURL)
            textSearch.invalidateResults(for: notification.projectURL)
        }
        .overlay {
            ProjectFileSearchOverlay(
                viewModel: fileSearch,
                openFile: { url in
                    openFilePreservingSelectedTab(url, activationFocusBehavior: .focusTextView)
                }
            )
        }
        .overlay {
            ProjectTextSearchOverlay(
                viewModel: textSearch,
                openResult: { result in
                    openTextSearchResult(result)
                }
            )
        }
        .overlay {
            CodeUsageOverlay(
                viewModel: codeUsage,
                openResult: { result in
                    openCodeUsageResult(result)
                }
            )
        }
        .overlay(alignment: .bottom) {
            if let codeNavigationToast {
                CodeNavigationToastView(
                    message: codeNavigationToast.message,
                    systemImage: codeNavigationToast.systemImage
                )
                    .padding(.bottom, 18)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.16), value: codeNavigationToast?.id)
        .background(
            DoubleShiftKeyDetector {
                fileSearch.present(projectURL: editor.projectURL)
            }
            .frame(width: 0, height: 0)
        )
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await openProject(url)
                }

            case .failure(let error):
                editor.presentError(error)
            }
        }
        .sheet(isPresented: $isNewWorktreeSheetPresented) {
            NewWorktreeSheet(
                source: $newWorktreeSource,
                branchName: $newWorktreeBranchName,
                initializationCommand: $newWorktreeInitializationCommand,
                remoteSearchText: $remoteWorktreeSearchText,
                selectedRemoteBranchID: $selectedRemoteWorktreeBranchID,
                isCreating: isCreatingWorktree,
                isRetryingInitialization: pendingInitializationWorkspaceID != nil,
                errorMessage: newWorktreeErrorMessage,
                remoteBranches: remoteWorktreeBranches,
                isLoadingRemoteBranches: isLoadingRemoteWorktreeBranches,
                remoteErrorMessage: remoteWorktreeErrorMessage,
                create: {
                    createWorktree()
                },
                cancel: {
                    guard !isCreatingWorktree else { return }
                    isNewWorktreeSheetPresented = false
                },
                loadRemoteBranches: {
                    loadRemoteWorktreeBranches(refresh: true)
                }
            )
        }
        .alert(
            AppText.deleteWorktreeAlertTitle,
            isPresented: Binding(
                get: { worktreeDeletionTarget != nil },
                set: { if !$0 && !isDeletingWorktree { worktreeDeletionTarget = nil } }
            )
        ) {
            Button(AppText.deleteButton, role: .destructive) {
                deleteWorktree()
            }
            .disabled(isDeletingWorktree)

            Button(AppText.cancelButton, role: .cancel) {
                guard !isDeletingWorktree else { return }
                worktreeDeletionTarget = nil
            }
            .disabled(isDeletingWorktree)
        } message: {
            if let worktreeDeletionTarget {
                Text(worktreeDeletionTarget.displayName)
                Text(worktreeDeletionTarget.displayPath)
            }
            Text(AppText.deleteWorktreeAlertMessage)
        }
        .alert(
            AppText.errorTitle,
            isPresented: Binding(
                get: { editor.currentError != nil },
                set: { if !$0 { editor.clearError() } }
            )
        ) {
            Button(AppText.okButton) {
                editor.clearError()
            }
        } message: {
            Text(editor.errorMessage ?? "")
        }
        .alert(
            AppText.externalPullRequestWorktreeAlertTitle,
            isPresented: Binding(
                get: { editor.externalPullRequestWorktreeCreationRequest != nil },
                set: { if !$0 { editor.cancelExternalPullRequestWorktreeCreation() } }
            )
        ) {
            Button(AppText.createButton) {
                let request = editor.externalPullRequestWorktreeCreationRequest
                Task {
                    await editor.confirmExternalPullRequestWorktreeCreation(request)
                }
            }

            Button(AppText.cancelButton, role: .cancel) {
                editor.cancelExternalPullRequestWorktreeCreation()
            }
        } message: {
            if let request = editor.externalPullRequestWorktreeCreationRequest {
                Text("Create a worktree for PR #\(request.pullRequestNumber) from \(request.remoteBranchName)?")
            }
        }
        .alert(
            AppText.errorTitle,
            isPresented: Binding(
                get: { githubAuth.currentError != nil },
                set: { if !$0 { githubAuth.clearError() } }
            )
        ) {
            Button(AppText.okButton) {
                githubAuth.clearError()
            }
        } message: {
            Text(githubAuth.errorMessage ?? "")
        }
        .alert(
            AppText.githubLoginAlertTitle,
            isPresented: Binding(
                get: { githubAuth.loginDevicePrompt != nil },
                set: { if !$0 { githubAuth.clearLoginDevicePrompt() } }
            )
        ) {
            Button(AppText.okButton) {
                githubAuth.clearLoginDevicePrompt()
            }
        } message: {
            if let prompt = githubAuth.loginDevicePrompt {
                Text("ブラウザでGitHubを開きました。コード \(prompt.userCode) を入力してください。コードはクリップボードにもコピー済みです。")
            }
        }
        .alert(
            AppText.saveConflictAlertTitle,
            isPresented: Binding(
                get: { editor.saveConflictConfirmation != nil },
                set: { if !$0 { editor.cancelSaveConflict() } }
            )
        ) {
            Button(AppText.overwriteButton, role: .destructive) {
                Task {
                    await editor.confirmSaveConflictOverwrite()
                }
            }
            Button(AppText.cancelButton, role: .cancel) {
                editor.cancelSaveConflict()
            }
        } message: {
            Text(editor.saveConflictConfirmationMessage ?? "")
            Text(AppText.saveConflictAlertMessage)
        }
        .alert(
            AppText.terminalCloseAlertTitle,
            isPresented: Binding(
                get: { terminalState.closeConfirmation != nil },
                set: { if !$0 { terminalState.cancelCloseTerminalTab() } }
            )
        ) {
            Button(AppText.terminateButton, role: .destructive) {
                terminalState.confirmCloseTerminalTab()
            }
            Button(AppText.cancelButton, role: .cancel) {
                terminalState.cancelCloseTerminalTab()
            }
        } message: {
            Text(terminalState.closeConfirmationMessage ?? "")
            Text(AppText.terminalCloseAlertMessage)
        }
    }

    private func presentNewWorktreeSheet() {
        newWorktreeSource = .local
        newWorktreeBranchName = ""
        newWorktreeInitializationCommand = worktreeInitialization.command
        pendingInitializationWorkspaceID = nil
        remoteWorktreeSearchText = ""
        selectedRemoteWorktreeBranchID = nil
        remoteWorktreeBranches = []
        remoteWorktreeErrorMessage = nil
        isLoadingRemoteWorktreeBranches = false
        newWorktreeErrorMessage = nil
        isCreatingWorktree = false
        isNewWorktreeSheetPresented = true
    }

    private func createWorktree() {
        guard !isCreatingWorktree else { return }

        if let pendingInitializationWorkspaceID {
            initializePendingWorktree(pendingInitializationWorkspaceID)
            return
        }

        let source = newWorktreeSource
        let localBranchName = newWorktreeBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let initializationCommand = newWorktreeInitializationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedRemoteBranchFullName = selectedRemoteWorktreeBranch?.fullName
        switch source {
        case .local:
            guard !localBranchName.isEmpty else { return }
        case .remote:
            guard selectedRemoteBranchFullName != nil else { return }
        }

        isCreatingWorktree = true
        newWorktreeErrorMessage = nil

        Task {
            do {
                try await worktreeInitialization.saveCommand(initializationCommand)
                let workspaceID: ProjectWorkspaceSnapshot.ID
                switch source {
                case .local:
                    workspaceID = try await editor.createWorktree(named: localBranchName)
                    newWorktreeBranchName = ""

                case .remote:
                    workspaceID = try await editor.createWorktree(
                        fromRemoteBranch: selectedRemoteBranchFullName ?? ""
                    )
                    remoteWorktreeSearchText = ""
                    selectedRemoteWorktreeBranchID = nil
                }
                pendingInitializationWorkspaceID = workspaceID
                try await editor.initializeWorktree(workspaceID, command: initializationCommand)
                pendingInitializationWorkspaceID = nil
                isNewWorktreeSheetPresented = false
            } catch {
                newWorktreeErrorMessage = error.localizedDescription
            }

            isCreatingWorktree = false
        }
    }

    private func initializePendingWorktree(_ workspaceID: ProjectWorkspaceSnapshot.ID) {
        let initializationCommand = newWorktreeInitializationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreatingWorktree = true
        newWorktreeErrorMessage = nil

        Task {
            do {
                try await worktreeInitialization.saveCommand(initializationCommand)
                try await editor.initializeWorktree(workspaceID, command: initializationCommand)
                pendingInitializationWorkspaceID = nil
                isNewWorktreeSheetPresented = false
            } catch {
                newWorktreeErrorMessage = error.localizedDescription
            }

            isCreatingWorktree = false
        }
    }

    private var selectedRemoteWorktreeBranch: GitRemoteBranchInfo? {
        guard let selectedRemoteWorktreeBranchID else { return nil }
        return remoteWorktreeBranches.first { $0.id == selectedRemoteWorktreeBranchID }
    }

    private func loadRemoteWorktreeBranches(refresh: Bool) {
        guard !isLoadingRemoteWorktreeBranches,
              editor.canCreateWorktree else {
            return
        }

        isLoadingRemoteWorktreeBranches = true
        remoteWorktreeErrorMessage = nil

        Task {
            do {
                let branches = try await editor.remoteBranches(refresh: refresh)
                remoteWorktreeBranches = branches
                if let selectedRemoteWorktreeBranchID,
                   !branches.contains(where: { $0.id == selectedRemoteWorktreeBranchID }) {
                    self.selectedRemoteWorktreeBranchID = nil
                }
            } catch {
                remoteWorktreeErrorMessage = error.localizedDescription
            }

            isLoadingRemoteWorktreeBranches = false
        }
    }

    private func presentDeleteWorktreeConfirmation(for workspaceID: ProjectWorkspaceSnapshot.ID? = nil) {
        guard !isDeletingWorktree,
              let target = workspaceID.flatMap({ editor.worktreeDeletionTarget(for: $0) })
                ?? editor.activeWorktreeDeletionTarget else {
            return
        }

        worktreeDeletionTarget = target
    }

    private func deleteWorktree() {
        guard let target = worktreeDeletionTarget,
              !isDeletingWorktree else {
            return
        }

        worktreeDeletionTarget = nil
        isDeletingWorktree = true

        Task {
            do {
                let result = try await editor.deleteWorktree(target.workspaceID)
                editorRuntimeStore.closeWorkspace(result.workspaceID)
                terminalState.removeWorkspace(id: result.workspaceID)
            } catch {
                editor.presentError(error)
            }

            isDeletingWorktree = false
        }
    }

    private func pullWorktree(_ workspaceID: ProjectWorkspaceSnapshot.ID) {
        Task {
            do {
                try await editor.pullWorktree(workspaceID)
                showCodeNavigationToast("Pull completed.", systemImage: "checkmark.circle")
            } catch {
                editor.presentError(error)
            }
        }
    }

    private func switchGitBranch(named branchName: String) {
        Task {
            do {
                try await editor.switchGitBranch(named: branchName)
            } catch {
                editor.presentError(error)
            }
        }
    }

    private func refreshGitHubAuthStatus() {
        Task {
            await githubAuth.refresh()
            editor.refreshGitHubPullRequest()
        }
    }

    private func logInToGitHub() {
        Task {
            await githubAuth.logIn()
            editor.refreshGitHubPullRequest()
        }
    }

    private func syncTerminalWorkspace() {
        terminalState.updateActiveWorkspace(
            id: editor.activeProjectID,
            rootURL: editor.projectURL,
            agentStatusDirectoryURL: editor.agentStatusDirectoryURL
        )
        runConfigurationState.updateMetadataLocation(editor.runConfigurationMetadataLocation)
        worktreeInitialization.updateMetadataLocation(editor.worktreeInitializationMetadataLocation)
    }

    private func openProject(_ url: URL) async {
        let result = await editor.openProject(url)
        if case .requiresNewWindow(let url) = result {
            openProjectInNewWindow(url)
        }
    }

    private func openFile(
        _ url: URL,
        activationFocusBehavior: EditorActivationFocusBehavior
    ) {
        editorRuntimeStore.requestActivationFocusBehavior(activationFocusBehavior, for: url)

        Task {
            if let closedDocument = await editor.openFile(url) {
                editorRuntimeStore.closeDocument(
                    workspaceID: closedDocument.workspaceID,
                    documentID: closedDocument.documentID
                )
            }
        }
    }

    private func openFilePreservingSelectedTab(
        _ url: URL,
        activationFocusBehavior: EditorActivationFocusBehavior
    ) {
        editorRuntimeStore.requestActivationFocusBehavior(activationFocusBehavior, for: url)

        Task {
            if let closedDocument = await editor.openFilePreservingSelectedTab(url) {
                editorRuntimeStore.closeDocument(
                    workspaceID: closedDocument.workspaceID,
                    documentID: closedDocument.documentID
                )
            }
        }
    }

    private func openTextSearchResult(_ result: ProjectTextSearchResult) {
        editorRuntimeStore.requestActivationFocusBehavior(.focusTextView, for: result.url)

        Task {
            if let closedDocument = await editor.navigateToFileRange(result.url, range: result.matchRange.nsRange) {
                editorRuntimeStore.closeDocument(
                    workspaceID: closedDocument.workspaceID,
                    documentID: closedDocument.documentID
                )
            }
        }
    }

    private func resolveImplementationOrReferences(at utf16Offset: Int, in tabID: EditorTab.ID) {
        Task {
            guard let result = await editor.resolveImplementationOrReferences(at: utf16Offset, in: tabID) else {
                showCodeNavigationToast(codeNavigationFailureMessage)
                return
            }

            handleCodeNavigationResult(result)
        }
    }

    private func resolveReviewDiffImplementationOrReferences(_ request: ReviewDiffCodeNavigationRequest) {
        Task {
            guard let result = await editor.resolveReviewDiffImplementationOrReferences(request) else {
                showCodeNavigationToast(codeNavigationFailureMessage)
                return
            }

            handleCodeNavigationResult(result)
        }
    }

    private func handleCodeNavigationResult(_ result: EditorCodeNavigationResult) {
        switch result {
        case .navigated(let closedDocument):
            clearCodeNavigationToast()
            if let closedDocument {
                editorRuntimeStore.closeDocument(
                    workspaceID: closedDocument.workspaceID,
                    documentID: closedDocument.documentID
                )
            }

        case .references(let results, let title):
            clearCodeNavigationToast()
            codeUsage.present(results: results, title: title)
        }
    }

    private func openCodeUsageResult(_ result: CodeUsageResult) {
        editorRuntimeStore.requestActivationFocusBehavior(.focusTextView, for: result.url)

        Task {
            if let closedDocument = await editor.navigateToCodeUsage(result) {
                editorRuntimeStore.closeDocument(
                    workspaceID: closedDocument.workspaceID,
                    documentID: closedDocument.documentID
                )
            }
        }
    }

    private var codeNavigationFailureMessage: String {
        switch editor.symbolIndexStatus {
        case .inactive, .failed:
            editor.symbolIndexStatus.detail
        case .indexing:
            "Symbol index is still building."
        case .ready:
            "No symbol or usages found."
        }
    }

    private func showCodeNavigationToast(
        _ message: String,
        systemImage: String = "exclamationmark.circle"
    ) {
        codeNavigationToastTask?.cancel()
        let toast = CodeNavigationToast(message: message, systemImage: systemImage)
        codeNavigationToast = toast
        codeNavigationToastTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_400_000_000)
            } catch {
                return
            }

            guard codeNavigationToast?.id == toast.id else { return }
            codeNavigationToast = nil
            codeNavigationToastTask = nil
        }
    }

    private func clearCodeNavigationToast() {
        codeNavigationToastTask?.cancel()
        codeNavigationToastTask = nil
        codeNavigationToast = nil
    }
}

private struct CodeNavigationToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
}

private enum NewWorktreeSource: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: Self {
        self
    }
}

private struct NewWorktreeSheet: View {
    @Binding var source: NewWorktreeSource
    @Binding var branchName: String
    @Binding var initializationCommand: String
    @Binding var remoteSearchText: String
    @Binding var selectedRemoteBranchID: GitRemoteBranchInfo.ID?
    let isCreating: Bool
    let isRetryingInitialization: Bool
    let errorMessage: String?
    let remoteBranches: [GitRemoteBranchInfo]
    let isLoadingRemoteBranches: Bool
    let remoteErrorMessage: String?
    let create: () -> Void
    let cancel: () -> Void
    let loadRemoteBranches: () -> Void

    private var trimmedBranchName: String {
        branchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRemoteSearchText: String {
        remoteSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRemoteBranches: [GitRemoteBranchInfo] {
        guard !trimmedRemoteSearchText.isEmpty else {
            return remoteBranches
        }

        return remoteBranches.filter { branch in
            branch.fullName.localizedCaseInsensitiveContains(trimmedRemoteSearchText)
                || branch.branchName.localizedCaseInsensitiveContains(trimmedRemoteSearchText)
        }
    }

    private var selectedRemoteBranch: GitRemoteBranchInfo? {
        guard let selectedRemoteBranchID else { return nil }
        return remoteBranches.first { $0.id == selectedRemoteBranchID }
    }

    private var canCreate: Bool {
        guard !isCreating else { return false }

        if isRetryingInitialization {
            return true
        }

        switch source {
        case .local:
            return !trimmedBranchName.isEmpty
        case .remote:
            return selectedRemoteBranch != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppText.newWorktreeTitle)
                .font(.headline)

            Picker("Worktree Source", selection: $source) {
                Text(AppText.newWorktreeLocalSource).tag(NewWorktreeSource.local)
                Text(AppText.newWorktreeRemoteSource).tag(NewWorktreeSource.remote)
            }
            .pickerStyle(.segmented)
            .disabled(isCreating)

            switch source {
            case .local:
                localBranchForm
            case .remote:
                remoteBranchForm
            }

            initializationForm

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button(AppText.cancelButton) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

                Button {
                    create()
                } label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRetryingInitialization ? AppText.retryInitializationButton : AppText.createButton)
                    }
                    .frame(minWidth: isRetryingInitialization ? 132 : 74)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if source == .remote {
                loadRemoteBranches()
            }
        }
        .onChange(of: source) { _, newSource in
            if newSource == .remote {
                loadRemoteBranches()
            }
        }
        .onChange(of: remoteSearchText) { _, _ in
            clearHiddenRemoteSelection()
        }
    }

    private var localBranchForm: some View {
        TextField(AppText.newWorktreeBranchPlaceholder, text: $branchName)
            .textFieldStyle(.roundedBorder)
            .disabled(isCreating)
            .onSubmit {
                guard canCreate else { return }
                create()
            }
    }

    private var initializationForm: some View {
        TextField(AppText.worktreeInitializationCommandPlaceholder, text: $initializationCommand)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .disabled(isCreating)
            .onSubmit {
                guard canCreate else { return }
                create()
            }
    }

    private var remoteBranchForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppText.newWorktreeRemoteSearchPlaceholder, text: $remoteSearchText)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreating || (isLoadingRemoteBranches && remoteBranches.isEmpty))

            if let remoteErrorMessage,
               !remoteErrorMessage.isEmpty,
               remoteBranches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(remoteErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(AppText.retryButton) {
                        loadRemoteBranches()
                    }
                    .disabled(isCreating || isLoadingRemoteBranches)
                }
                .frame(minHeight: 180, alignment: .center)
            } else if isLoadingRemoteBranches && remoteBranches.isEmpty {
                ProgressView(AppText.newWorktreeFetchingRemoteBranches)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if filteredRemoteBranches.isEmpty {
                ContentUnavailableView(
                    remoteBranches.isEmpty
                        ? AppText.newWorktreeNoRemoteBranches
                        : AppText.newWorktreeNoRemoteBranchMatches,
                    systemImage: "arrow.triangle.branch"
                )
                .frame(minHeight: 180)
            } else {
                List(selection: $selectedRemoteBranchID) {
                    ForEach(filteredRemoteBranches) { branch in
                        RemoteBranchRow(branch: branch)
                            .tag(branch.id)
                    }
                }
                .frame(minHeight: 180, idealHeight: 240)
                .disabled(isCreating)

                if isLoadingRemoteBranches {
                    ProgressView(AppText.newWorktreeFetchingRemoteBranches)
                        .controlSize(.small)
                }
            }
        }
    }

    private func clearHiddenRemoteSelection() {
        guard let selectedRemoteBranchID,
              !filteredRemoteBranches.contains(where: { $0.id == selectedRemoteBranchID }) else {
            return
        }

        self.selectedRemoteBranchID = nil
    }
}

private struct RemoteBranchRow: View {
    let branch: GitRemoteBranchInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.branchName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(branch.remoteName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct CodeNavigationToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: systemImage)
                .imageScale(.medium)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }
}

#Preview {
    ContentView(
        editor: EditorState(),
        editorRuntimeStore: EditorRuntimeStore(),
        terminalState: TerminalState(),
        runConfigurationState: RunConfigurationState(),
        textSearch: ProjectTextSearchViewModel(),
        tabInputSettings: EditorTabInputSettingsStore(),
        lineWrappingSettings: EditorLineWrappingSettingsStore(),
        githubAuth: GitHubAuthViewModel(
            service: PreviewGitHubAuthService(),
            initialStatus: .unauthenticated
        ),
        isImporterPresented: .constant(false),
        isWorktreeOverviewVisible: .constant(true),
        openProjectInNewWindow: { _ in }
    )
}

private struct PreviewGitHubAuthService: GitHubAuthServiceProtocol {
    func currentAuthenticationStatus() async -> GitHubAuthStatusState {
        .unauthenticated
    }

    func logIn(devicePromptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void) async throws {
    }
}
