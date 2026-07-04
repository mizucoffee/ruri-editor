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

// MARK: - Status Bar State Models

struct TerminalStatusBarState: Equatable {
    let tabCount: Int
    let isMinimized: Bool
    let isEnabled: Bool

    var title: String {
        "Terminal \(tabCount)"
    }

    var toolTip: String {
        guard isEnabled else {
            return "Open a folder to use the terminal."
        }

        let action = isMinimized ? "Show" : "Hide"
        return "\(action) Terminal (\(tabCount) open)"
    }
}

struct GitStatusBarState: Equatable {
    let title: String?
    let toolTip: String?
    let accessibilityValue: String
    let branches: [GitStatusBarBranchState]
    let canSwitchBranch: Bool

    init(status: GitRepositoryStatus) {
        switch status {
        case .inactive:
            title = nil
            toolTip = nil
            accessibilityValue = ""
            branches = []
            canSwitchBranch = false

        case .checking:
            title = "Git"
            toolTip = "Checking Git repository status."
            accessibilityValue = "Checking Git repository status"
            branches = []
            canSwitchBranch = false

        case .notRepository(let url):
            title = "No Git"
            toolTip = "\(url.lastPathComponent) is not in a Git repository."
            accessibilityValue = "Not a Git repository"
            branches = []
            canSwitchBranch = false

        case .repository(let snapshot):
            if snapshot.isRuriStyleWorktree {
                title = "\(snapshot.branch.displayName) (worktree)"
                toolTip = "\(snapshot.branch.detail)\nruri-style worktree: \(snapshot.worktreeRootURL.path(percentEncoded: false))"
                accessibilityValue = "\(snapshot.branch.displayName), ruri-style worktree"
                branches = snapshot.localBranches.map { branch in
                    GitStatusBarBranchState(
                        name: branch.name,
                        isCurrent: branch.name == snapshot.branch.displayName,
                        checkedOutWorktreeURL: branch.checkedOutWorktreeURL,
                        currentWorktreeURL: snapshot.worktreeRootURL
                    )
                }
                canSwitchBranch = true
            } else {
                branches = []
                canSwitchBranch = false

                switch snapshot.worktreeKind {
                case .main:
                    if snapshot.hasOtherWorktrees {
                        title = "\(snapshot.branch.displayName) Worktree Root"
                        toolTip = "\(snapshot.branch.detail)\nWorktree root: \(snapshot.worktreeRootURL.path(percentEncoded: false))"
                        accessibilityValue = "\(snapshot.branch.displayName), worktree root"
                    } else {
                        title = snapshot.branch.displayName
                        toolTip = snapshot.branch.detail
                        accessibilityValue = snapshot.branch.displayName
                    }

                case .linked:
                    title = "\(snapshot.branch.displayName) Worktree"
                    toolTip = "\(snapshot.branch.detail)\nLinked worktree: \(snapshot.worktreeRootURL.path(percentEncoded: false))"
                    accessibilityValue = "\(snapshot.branch.displayName), linked worktree"
                }
            }
        }
    }
}

enum GitHubStatusBarAction: Equatable {
    case logIn
    case refresh
}

enum GitHubStatusBarTint: Equatable {
    case primary
    case secondary
    case tertiary
    case red
}

struct GitHubStatusBarState: Equatable {
    let title: String
    let toolTip: String
    let accessibilityValue: String
    let action: GitHubStatusBarAction?
    let tint: GitHubStatusBarTint

    init(status: GitHubAuthStatusState) {
        switch status {
        case .checking:
            title = "GitHub"
            toolTip = "Checking GitHub authentication."
            accessibilityValue = "Checking GitHub authentication"
            action = nil
            tint = .secondary

        case .authenticating:
            title = "GitHub"
            toolTip = "Starting GitHub login."
            accessibilityValue = "Starting GitHub login"
            action = nil
            tint = .secondary

        case .authenticated(let username):
            title = "@\(username)"
            toolTip = "Logged in to GitHub as \(username)."
            accessibilityValue = "Logged in to GitHub as \(username)"
            action = nil
            tint = .primary

        case .unauthenticated:
            title = "GitHub Login"
            toolTip = "Log in to GitHub with GitHub CLI."
            accessibilityValue = "Not logged in to GitHub"
            action = .logIn
            tint = .secondary

        case .unavailable(let message):
            title = "No gh"
            toolTip = message
            accessibilityValue = message
            action = nil
            tint = .tertiary

        case .failed(let message):
            title = "GitHub Error"
            toolTip = "\(message)\nClick to retry."
            accessibilityValue = "GitHub authentication failed"
            action = .refresh
            tint = .red
        }
    }
}

struct GitHubPullRequestStatusBarState: Equatable {
    let title: String
    let toolTip: String
    let accessibilityValue: String
    let url: URL

    init?(status: GitHubPullRequestStatus?) {
        guard let status else { return nil }

        switch status {
        case .pullRequest(let pullRequest):
            title = pullRequest.isDraft ? "\(pullRequest.displayTitle) Draft" : pullRequest.displayTitle
            toolTip = "View pull request \(pullRequest.displayTitle), \(pullRequest.displayStateDescription)\n\(pullRequest.url.absoluteString)"
            accessibilityValue = "Pull request \(pullRequest.displayTitle), \(pullRequest.displayStateDescription)"
            url = pullRequest.url

        case .create(let creationLink):
            title = "Create PR"
            toolTip = "Create pull request \(creationLink.headBranch) into \(creationLink.baseBranch)\n\(creationLink.url.absoluteString)"
            accessibilityValue = "Create pull request"
            url = creationLink.url
        }
    }
}

struct GitStatusBarBranchState: Equatable {
    let name: String
    let isCurrent: Bool
    let checkedOutWorktreeURL: URL?
    let currentWorktreeURL: URL

    var isCheckedOutInOtherWorktree: Bool {
        guard let checkedOutWorktreeURL else { return false }
        return !FileURLRewriter.urlsMatch(checkedOutWorktreeURL, currentWorktreeURL)
    }

    var isSelectable: Bool {
        !isCheckedOutInOtherWorktree
    }

    var toolTip: String {
        if isCurrent {
            return "Current branch"
        }

        if let checkedOutWorktreeURL,
           isCheckedOutInOtherWorktree {
            return "Already checked out at \(checkedOutWorktreeURL.path(percentEncoded: false))"
        }

        return "Switch to \(name)"
    }
}
