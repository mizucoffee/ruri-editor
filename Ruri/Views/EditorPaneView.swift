//
//  EditorPaneView.swift
//  ruri
//

import SwiftUI

struct EditorPaneView: View {
    @ObservedObject var runtimeStore: EditorRuntimeStore
    @ObservedObject var terminalState: TerminalViewModel
    let paneFocus: PaneFocusStore
    @State private var reviewDiffDisplayMode = ReviewDiffDisplayMode.unified
    @State private var reviewDiffWrapLines = true

    let state: EditorPaneHostState
    let actions: EditorPaneHostActions

    var body: some View {
        EditorPaneHostView(
            state: state,
            actions: actions,
            reviewDiffDisplayMode: $reviewDiffDisplayMode,
            reviewDiffWrapLines: $reviewDiffWrapLines,
            runtimeStore: runtimeStore,
            paneFocus: paneFocus,
            terminalState: TerminalPaneHostState(
                workspaceURL: terminalState.activeWorkspaceURL,
                tabs: terminalState.tabs,
                selectedTabID: terminalState.selectedTabID,
                focusRequest: terminalState.focusRequest,
                isMinimized: terminalState.isMinimized
            ),
            terminalActions: TerminalPaneHostActions(
                terminalView: { terminalState.terminalView(for: $0) },
                createTab: { terminalState.createTab() },
                selectTab: { terminalState.selectTab($0) },
                closeTab: { terminalState.requestCloseTab($0) },
                toggleMinimized: { terminalState.toggleMinimized() }
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let document = OpenDocument(
        url: URL(filePath: "/tmp/TestFile.swift"),
        text: "print(\"Hello\")",
        lastSavedText: "",
        hasUserEdited: true
    )
    let tabModel = EditorTab(documentID: document.id)
    let tab = EditorTabSnapshot(
        id: tabModel.id,
        documentID: document.id,
        url: document.url,
        text: document.text,
        lastSavedText: document.lastSavedText,
        hasUserEdited: document.hasUserEdited,
        lastKnownFileSignature: document.lastKnownFileSignature,
        externalStatus: document.externalStatus
    )

    EditorPaneView(
        runtimeStore: EditorRuntimeStore(),
        terminalState: TerminalViewModel(),
        paneFocus: PaneFocusStore(),
        state: EditorPaneHostState(
            workspaceID: URL(filePath: "/tmp"),
            editorMode: .edit,
            reviewDiffState: .unavailable,
            reviewDiffBase: nil,
            reviewDiffRemoteBranches: [],
            isLoadingReviewDiffRemoteBranches: false,
            reviewDiffRemoteBranchErrorMessage: nil,
            reviewDiffHideWhitespace: false,
            reviewDiffViewedFilePaths: [],
            reviewDiffViewedSyncsToPullRequest: false,
            tabs: [tab],
            selectedTabID: tab.id,
            findPresentationRequest: nil,
            implementationJumpRequest: nil,
            symbolIndexStatus: .inactive,
            fileSearchIndexStatus: .inactive,
            gitRepositoryStatus: .inactive,
            gitSnapshot: nil,
            githubAuthStatus: .unauthenticated,
            githubPullRequestStatus: nil,
            isGithubPullRequestLoading: false,
            tabInputSetting: .defaultValue,
            lineWrappingMode: .defaultValue,
            visibleFocusedPane: nil
        ),
        actions: EditorPaneHostActions(
            editorSession: { _ in EditorDocumentSession() },
            updateText: { _, _ in },
            updateSelection: { _, _ in },
            updateScrollOrigin: { _, _ in },
            focusEditor: { _ in },
            blurEditor: { _ in },
            requestImplementationJump: { _, _ in },
            implementationHoverRange: { _, _ in nil },
            requestReviewDiffCodeNavigation: { _ in },
            reviewDiffCodeNavigationHoverRange: { _ in nil },
            selectTab: { _ in },
            setTabInputSetting: { _ in },
            switchGitBranch: { _ in },
            refreshGitHubAuthStatus: {},
            logInToGitHub: {},
            openGitHubPullRequest: { _ in },
            selectReviewDiffBase: { _ in },
            loadReviewDiffRemoteBranches: { _ in },
            refreshReviewDiff: {},
            setReviewDiffHideWhitespace: { _ in },
            setReviewDiffFileViewed: { _, _ in },
            openReviewDiffFile: { _ in },
            closeTab: { _ in },
            moveTab: { _, _ in }
        )
    )
}
