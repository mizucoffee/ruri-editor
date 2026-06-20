//
//  EditorPaneView.swift
//  ruri
//

import SwiftUI

struct EditorPaneView: View {
    @ObservedObject var runtimeStore: EditorRuntimeStore
    @ObservedObject var terminalState: TerminalState
    @State private var reviewDiffDisplayMode = ReviewDiffDisplayMode.unified
    @State private var reviewDiffWrapLines = true

    let workspaceID: ProjectWorkspaceSnapshot.ID?
    let editorMode: EditorMode
    let reviewDiffState: ReviewDiffState
    let reviewDiffBase: GitReviewDiffBase?
    let reviewDiffRemoteBranches: [GitRemoteBranchInfo]
    let isLoadingReviewDiffRemoteBranches: Bool
    let reviewDiffRemoteBranchErrorMessage: String?
    let reviewDiffHideWhitespace: Bool
    let tabs: [EditorTabSnapshot]
    let selectedTabID: EditorTab.ID?
    let symbolIndexStatus: SymbolIndexStatusState
    let fileSearchIndexStatus: ProjectFileSearchIndexStatusState
    let gitRepositoryStatus: GitRepositoryStatus
    let gitSnapshot: GitRepositorySnapshot?
    let githubAuthStatus: GitHubAuthStatusState
    let githubPullRequestStatus: GitHubPullRequestStatus?
    let tabInputSetting: EditorTabInputSetting
    let lineWrappingMode: EditorLineWrappingMode
    let editorSession: (EditorTab.ID) -> EditorDocumentSession?
    let updateText: (String, EditorTab.ID) -> Void
    let updateSelection: (NSRange, EditorTab.ID) -> Void
    let updateScrollOrigin: (CGPoint, EditorTab.ID) -> Void
    let requestImplementationJump: (EditorTab.ID, Int) -> Void
    let implementationHoverRange: (EditorTab.ID, Int) async -> NSRange?
    let requestReviewDiffCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let reviewDiffCodeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?
    let selectTab: (EditorTab.ID) -> Void
    let setTabInputSetting: (EditorTabInputSetting) -> Void
    let switchGitBranch: (String) -> Void
    let refreshGitHubAuthStatus: () -> Void
    let logInToGitHub: () -> Void
    let openGitHubPullRequest: (URL) -> Void
    let selectReviewDiffBase: (GitReviewDiffBase) -> Void
    let loadReviewDiffRemoteBranches: (Bool) -> Void
    let refreshReviewDiff: () -> Void
    let setReviewDiffHideWhitespace: (Bool) -> Void
    let openReviewDiffFile: (URL) -> Void
    let closeTab: (EditorTab.ID) -> Void
    let moveTab: (EditorTab.ID, EditorTab.ID) -> Void

    var body: some View {
        EditorPaneHostView(
            workspaceID: workspaceID,
            editorMode: editorMode,
            reviewDiffState: reviewDiffState,
            reviewDiffBase: reviewDiffBase,
            reviewDiffRemoteBranches: reviewDiffRemoteBranches,
            isLoadingReviewDiffRemoteBranches: isLoadingReviewDiffRemoteBranches,
            reviewDiffRemoteBranchErrorMessage: reviewDiffRemoteBranchErrorMessage,
            reviewDiffHideWhitespace: reviewDiffHideWhitespace,
            reviewDiffDisplayMode: $reviewDiffDisplayMode,
            reviewDiffWrapLines: $reviewDiffWrapLines,
            runtimeStore: runtimeStore,
            tabs: tabs,
            selectedTabID: selectedTabID,
            findPresentationRequest: runtimeStore.findPresentationRequest,
            implementationJumpRequest: runtimeStore.implementationJumpRequest,
            symbolIndexStatus: symbolIndexStatus,
            fileSearchIndexStatus: fileSearchIndexStatus,
            gitRepositoryStatus: gitRepositoryStatus,
            gitSnapshot: gitSnapshot,
            githubAuthStatus: githubAuthStatus,
            githubPullRequestStatus: githubPullRequestStatus,
            tabInputSetting: tabInputSetting,
            lineWrappingMode: lineWrappingMode,
            editorSession: editorSession,
            updateText: updateText,
            updateSelection: updateSelection,
            updateScrollOrigin: updateScrollOrigin,
            requestImplementationJump: requestImplementationJump,
            implementationHoverRange: implementationHoverRange,
            requestReviewDiffCodeNavigation: requestReviewDiffCodeNavigation,
            reviewDiffCodeNavigationHoverRange: reviewDiffCodeNavigationHoverRange,
            selectTab: selectTab,
            setTabInputSetting: setTabInputSetting,
            switchGitBranch: switchGitBranch,
            refreshGitHubAuthStatus: refreshGitHubAuthStatus,
            logInToGitHub: logInToGitHub,
            openGitHubPullRequest: openGitHubPullRequest,
            selectReviewDiffBase: selectReviewDiffBase,
            loadReviewDiffRemoteBranches: loadReviewDiffRemoteBranches,
            refreshReviewDiff: refreshReviewDiff,
            setReviewDiffHideWhitespace: setReviewDiffHideWhitespace,
            openReviewDiffFile: openReviewDiffFile,
            closeTab: closeTab,
            moveTab: moveTab,
            terminalWorkspaceURL: terminalState.activeWorkspaceURL,
            terminalTabs: terminalState.tabs,
            selectedTerminalTabID: terminalState.selectedTabID,
            terminalFocusRequest: terminalState.focusRequest,
            isTerminalMinimized: terminalState.isMinimized,
            terminalView: { terminalState.terminalView(for: $0) },
            createTerminalTab: { terminalState.createTab() },
            selectTerminalTab: { terminalState.selectTab($0) },
            closeTerminalTab: { terminalState.requestCloseTab($0) },
            toggleTerminalMinimized: { terminalState.toggleMinimized() }
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
        terminalState: TerminalState(),
        workspaceID: URL(filePath: "/tmp"),
        editorMode: .edit,
        reviewDiffState: .unavailable,
        reviewDiffBase: nil,
        reviewDiffRemoteBranches: [],
        isLoadingReviewDiffRemoteBranches: false,
        reviewDiffRemoteBranchErrorMessage: nil,
        reviewDiffHideWhitespace: false,
        tabs: [tab],
        selectedTabID: tab.id,
        symbolIndexStatus: .inactive,
        fileSearchIndexStatus: .inactive,
        gitRepositoryStatus: .inactive,
        gitSnapshot: nil,
        githubAuthStatus: .unauthenticated,
        githubPullRequestStatus: nil,
        tabInputSetting: .defaultValue,
        lineWrappingMode: .defaultValue,
        editorSession: { _ in EditorDocumentSession() },
        updateText: { _, _ in },
        updateSelection: { _, _ in },
        updateScrollOrigin: { _, _ in },
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
        openReviewDiffFile: { _ in },
        closeTab: { _ in },
        moveTab: { _, _ in }
    )
}
