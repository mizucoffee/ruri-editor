//
//  EditorPaneHostModels.swift
//  ruri
//

import AppKit
import SwiftUI

struct EditorPaneHostState {
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
    let findPresentationRequest: EditorFindPresentationRequest?
    let implementationJumpRequest: EditorImplementationJumpRequest?
    let symbolIndexStatus: SymbolIndexStatusState
    let fileSearchIndexStatus: ProjectFileSearchIndexStatusState
    let gitRepositoryStatus: GitRepositoryStatus
    let gitSnapshot: GitRepositorySnapshot?
    let githubAuthStatus: GitHubAuthStatusState
    let githubPullRequestStatus: GitHubPullRequestStatus?
    let tabInputSetting: EditorTabInputSetting
    let lineWrappingMode: EditorLineWrappingMode
}

struct EditorPaneHostActions {
    let editorSession: (EditorTab.ID) -> EditorDocumentSession?
    let updateText: (String, EditorTab.ID) -> Void
    let updateSelection: (NSRange, EditorTab.ID) -> Void
    let updateScrollOrigin: (CGPoint, EditorTab.ID) -> Void
    let focusEditor: (EditorTab.ID) -> Void
    let blurEditor: (EditorTab.ID) -> Void
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
}

struct TerminalPaneHostState {
    let workspaceURL: URL?
    let tabs: [TerminalTabSnapshot]
    let selectedTabID: TerminalTab.ID?
    let focusRequest: TerminalFocusRequest?
    let isMinimized: Bool
}

struct TerminalPaneHostActions {
    let terminalView: (TerminalTab.ID) -> NSView?
    let createTab: () -> Void
    let selectTab: (TerminalTab.ID) -> Void
    let closeTab: (TerminalTab.ID) -> Void
    let toggleMinimized: () -> Void
}
