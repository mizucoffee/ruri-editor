//
//  EditorPaneHostModelsTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorPaneHostModelsTests: XCTestCase {
    // MARK: - TerminalStatusBarState

    func testTerminalTitleInterpolatesTabCount() {
        let state = TerminalStatusBarState(tabCount: 3, isMinimized: false, isEnabled: true)

        XCTAssertEqual(state.title, "Terminal 3")
    }

    func testTerminalToolTipWhenDisabled() {
        let state = TerminalStatusBarState(tabCount: 2, isMinimized: false, isEnabled: false)

        XCTAssertEqual(state.toolTip, "Open a folder to use the terminal.")
    }

    func testTerminalToolTipWhenMinimized() {
        let state = TerminalStatusBarState(tabCount: 2, isMinimized: true, isEnabled: true)

        XCTAssertEqual(state.toolTip, "Show Terminal (2 open)")
    }

    func testTerminalToolTipWhenVisible() {
        let state = TerminalStatusBarState(tabCount: 1, isMinimized: false, isEnabled: true)

        XCTAssertEqual(state.toolTip, "Hide Terminal (1 open)")
    }

    // MARK: - GitStatusBarState

    func testGitStateForInactiveStatus() {
        let state = GitStatusBarState(status: .inactive)

        XCTAssertNil(state.title)
        XCTAssertNil(state.toolTip)
        XCTAssertEqual(state.accessibilityValue, "")
        XCTAssertEqual(state.branches, [])
        XCTAssertFalse(state.canSwitchBranch)
    }

    func testGitStateForCheckingStatus() {
        let state = GitStatusBarState(status: .checking)

        XCTAssertEqual(state.title, "Git")
        XCTAssertEqual(state.toolTip, "Checking Git repository status.")
        XCTAssertEqual(state.accessibilityValue, "Checking Git repository status")
        XCTAssertEqual(state.branches, [])
        XCTAssertFalse(state.canSwitchBranch)
    }

    func testGitStateForNotRepositoryStatusUsesLastPathComponent() {
        let state = GitStatusBarState(status: .notRepository(URL(filePath: "/tmp/example/project")))

        XCTAssertEqual(state.title, "No Git")
        XCTAssertEqual(state.toolTip, "project is not in a Git repository.")
        XCTAssertEqual(state.accessibilityValue, "Not a Git repository")
        XCTAssertEqual(state.branches, [])
        XCTAssertFalse(state.canSwitchBranch)
    }

    func testGitStateForRuriStyleWorktreeMapsBranchesAndEnablesSwitching() {
        // worktreeKind is .linked to pin that the ruri-style check wins over the kind switch.
        let snapshot = makeSnapshot(
            worktreeKind: .linked,
            isRuriStyleWorktree: true,
            localBranches: [
                GitLocalBranchInfo(name: "main", checkedOutWorktreeURL: URL(filePath: "/tmp/repo-main")),
                GitLocalBranchInfo(name: "feature/login", checkedOutWorktreeURL: URL(filePath: "/tmp/repo")),
                GitLocalBranchInfo(name: "experiment", checkedOutWorktreeURL: nil)
            ],
            branch: .branch("feature/login")
        )

        let state = GitStatusBarState(status: .repository(snapshot))

        XCTAssertEqual(state.title, "feature/login (worktree)")
        XCTAssertEqual(state.toolTip, "On branch feature/login\nruri-style worktree: /tmp/repo")
        XCTAssertEqual(state.accessibilityValue, "feature/login, ruri-style worktree")
        XCTAssertTrue(state.canSwitchBranch)
        XCTAssertEqual(state.branches, [
            GitStatusBarBranchState(
                name: "main",
                isCurrent: false,
                checkedOutWorktreeURL: URL(filePath: "/tmp/repo-main"),
                currentWorktreeURL: URL(filePath: "/tmp/repo")
            ),
            GitStatusBarBranchState(
                name: "feature/login",
                isCurrent: true,
                checkedOutWorktreeURL: URL(filePath: "/tmp/repo"),
                currentWorktreeURL: URL(filePath: "/tmp/repo")
            ),
            GitStatusBarBranchState(
                name: "experiment",
                isCurrent: false,
                checkedOutWorktreeURL: nil,
                currentWorktreeURL: URL(filePath: "/tmp/repo")
            )
        ])
    }

    func testGitStateForMainWorktreeWithoutOthers() {
        let state = GitStatusBarState(status: .repository(makeSnapshot()))

        XCTAssertEqual(state.title, "main")
        XCTAssertEqual(state.toolTip, "On branch main")
        XCTAssertEqual(state.accessibilityValue, "main")
        XCTAssertEqual(state.branches, [])
        XCTAssertFalse(state.canSwitchBranch)
    }

    func testGitStateForMainWorktreeWithOtherWorktrees() {
        let snapshot = makeSnapshot(
            worktreeRootURLs: [URL(filePath: "/tmp/repo"), URL(filePath: "/tmp/repo-w1")]
        )

        let state = GitStatusBarState(status: .repository(snapshot))

        XCTAssertEqual(state.title, "main Worktree Root")
        XCTAssertEqual(state.toolTip, "On branch main\nWorktree root: /tmp/repo")
        XCTAssertEqual(state.accessibilityValue, "main, worktree root")
        XCTAssertEqual(state.branches, [])
        XCTAssertFalse(state.canSwitchBranch)
    }

    func testGitStateForLinkedWorktree() {
        let state = GitStatusBarState(status: .repository(makeSnapshot(worktreeKind: .linked)))

        XCTAssertEqual(state.title, "main Worktree")
        XCTAssertEqual(state.toolTip, "On branch main\nLinked worktree: /tmp/repo")
        XCTAssertEqual(state.accessibilityValue, "main, linked worktree")
        XCTAssertEqual(state.branches, [])
        XCTAssertFalse(state.canSwitchBranch)
    }

    // MARK: - GitHubStatusBarState

    func testGitHubStateForChecking() {
        let state = GitHubStatusBarState(status: .checking)

        XCTAssertEqual(state.title, "GitHub")
        XCTAssertEqual(state.toolTip, "Checking GitHub authentication.")
        XCTAssertEqual(state.accessibilityValue, "Checking GitHub authentication")
        XCTAssertNil(state.action)
        XCTAssertEqual(state.tint, .secondary)
    }

    func testGitHubStateForAuthenticating() {
        let state = GitHubStatusBarState(status: .authenticating)

        XCTAssertEqual(state.title, "GitHub")
        XCTAssertEqual(state.toolTip, "Starting GitHub login.")
        XCTAssertEqual(state.accessibilityValue, "Starting GitHub login")
        XCTAssertNil(state.action)
        XCTAssertEqual(state.tint, .secondary)
    }

    func testGitHubStateForAuthenticated() {
        let state = GitHubStatusBarState(status: .authenticated(username: "octocat"))

        XCTAssertEqual(state.title, "@octocat")
        XCTAssertEqual(state.toolTip, "Logged in to GitHub as octocat.")
        XCTAssertEqual(state.accessibilityValue, "Logged in to GitHub as octocat")
        XCTAssertNil(state.action)
        XCTAssertEqual(state.tint, .primary)
    }

    func testGitHubStateForUnauthenticated() {
        let state = GitHubStatusBarState(status: .unauthenticated)

        XCTAssertEqual(state.title, "GitHub Login")
        XCTAssertEqual(state.toolTip, "Log in to GitHub with GitHub CLI.")
        XCTAssertEqual(state.accessibilityValue, "Not logged in to GitHub")
        XCTAssertEqual(state.action, .logIn)
        XCTAssertEqual(state.tint, .secondary)
    }

    func testGitHubStateForUnavailable() {
        let state = GitHubStatusBarState(status: .unavailable(message: "gh not found"))

        XCTAssertEqual(state.title, "No gh")
        XCTAssertEqual(state.toolTip, "gh not found")
        XCTAssertEqual(state.accessibilityValue, "gh not found")
        XCTAssertNil(state.action)
        XCTAssertEqual(state.tint, .tertiary)
    }

    func testGitHubStateForFailed() {
        let state = GitHubStatusBarState(status: .failed(message: "boom"))

        XCTAssertEqual(state.title, "GitHub Error")
        XCTAssertEqual(state.toolTip, "boom\nClick to retry.")
        XCTAssertEqual(state.accessibilityValue, "GitHub authentication failed")
        XCTAssertEqual(state.action, .refresh)
        XCTAssertEqual(state.tint, .red)
    }

    // MARK: - GitHubPullRequestStatusBarState

    func testPullRequestStateIsNilWithoutStatus() {
        XCTAssertNil(GitHubPullRequestStatusBarState(status: nil))
    }

    func testPullRequestStateForOpenPullRequest() {
        let url = URL(string: "https://github.com/example/repo/pull/12")!
        let status = GitHubPullRequestStatus.pullRequest(
            GitHubPullRequestInfo(number: 12, url: url, lifecycleState: .open)
        )

        let state = GitHubPullRequestStatusBarState(status: status)

        XCTAssertEqual(state?.title, "#12")
        XCTAssertEqual(state?.toolTip, "View pull request #12, Open\n\(url.absoluteString)")
        XCTAssertEqual(state?.accessibilityValue, "Pull request #12, Open")
        XCTAssertEqual(state?.url, url)
    }

    func testPullRequestStateForDraftPullRequest() {
        let url = URL(string: "https://github.com/example/repo/pull/12")!
        let status = GitHubPullRequestStatus.pullRequest(
            GitHubPullRequestInfo(number: 12, url: url, isDraft: true, lifecycleState: .open)
        )

        let state = GitHubPullRequestStatusBarState(status: status)

        XCTAssertEqual(state?.title, "#12 Draft")
        XCTAssertEqual(state?.toolTip, "View pull request #12, Draft, Open\n\(url.absoluteString)")
        XCTAssertEqual(state?.accessibilityValue, "Pull request #12, Draft, Open")
        XCTAssertEqual(state?.url, url)
    }

    func testPullRequestStateForCreationLink() {
        let url = URL(string: "https://github.com/example/repo/compare/main...feature/login")!
        let status = GitHubPullRequestStatus.create(
            GitHubPullRequestCreationLink(baseBranch: "main", headBranch: "feature/login", url: url)
        )

        let state = GitHubPullRequestStatusBarState(status: status)

        XCTAssertEqual(state?.title, "Create PR")
        XCTAssertEqual(state?.toolTip, "Create pull request feature/login into main\n\(url.absoluteString)")
        XCTAssertEqual(state?.accessibilityValue, "Create pull request")
        XCTAssertEqual(state?.url, url)
    }

    // MARK: - GitStatusBarBranchState

    func testBranchStateForCurrentBranch() {
        let state = GitStatusBarBranchState(
            name: "main",
            isCurrent: true,
            checkedOutWorktreeURL: URL(filePath: "/tmp/repo"),
            currentWorktreeURL: URL(filePath: "/tmp/repo")
        )

        XCTAssertFalse(state.isCheckedOutInOtherWorktree)
        XCTAssertTrue(state.isSelectable)
        XCTAssertEqual(state.toolTip, "Current branch")
    }

    func testBranchStateWithoutCheckoutIsSelectable() {
        let state = GitStatusBarBranchState(
            name: "feature/login",
            isCurrent: false,
            checkedOutWorktreeURL: nil,
            currentWorktreeURL: URL(filePath: "/tmp/repo")
        )

        XCTAssertFalse(state.isCheckedOutInOtherWorktree)
        XCTAssertTrue(state.isSelectable)
        XCTAssertEqual(state.toolTip, "Switch to feature/login")
    }

    func testBranchStateMatchesWorktreeURLsIgnoringTrailingSlash() {
        let state = GitStatusBarBranchState(
            name: "feature/login",
            isCurrent: false,
            checkedOutWorktreeURL: URL(filePath: "/tmp/repo/"),
            currentWorktreeURL: URL(filePath: "/tmp/repo")
        )

        XCTAssertFalse(state.isCheckedOutInOtherWorktree)
        XCTAssertTrue(state.isSelectable)
        XCTAssertEqual(state.toolTip, "Switch to feature/login")
    }

    func testBranchStateCheckedOutInOtherWorktreeIsNotSelectable() {
        let state = GitStatusBarBranchState(
            name: "feature/login",
            isCurrent: false,
            checkedOutWorktreeURL: URL(filePath: "/tmp/other"),
            currentWorktreeURL: URL(filePath: "/tmp/repo")
        )

        XCTAssertTrue(state.isCheckedOutInOtherWorktree)
        XCTAssertFalse(state.isSelectable)
        XCTAssertEqual(state.toolTip, "Already checked out at /tmp/other")
    }

    func testBranchStateCurrentToolTipWinsOverOtherWorktree() {
        let state = GitStatusBarBranchState(
            name: "main",
            isCurrent: true,
            checkedOutWorktreeURL: URL(filePath: "/tmp/other"),
            currentWorktreeURL: URL(filePath: "/tmp/repo")
        )

        XCTAssertEqual(state.toolTip, "Current branch")
        XCTAssertFalse(state.isSelectable)
    }

    // MARK: - Helpers

    private func makeSnapshot(
        worktreeRootURL: URL = URL(filePath: "/tmp/repo"),
        worktreeKind: GitWorktreeKind = .main,
        worktreeRootURLs: [URL]? = nil,
        isRuriStyleWorktree: Bool = false,
        localBranches: [GitLocalBranchInfo] = [],
        branch: GitBranchState = .branch("main")
    ) -> GitRepositorySnapshot {
        GitRepositorySnapshot(
            repositoryRootURL: worktreeRootURL,
            worktreeRootURL: worktreeRootURL,
            openedRootURL: worktreeRootURL,
            gitDirectoryURL: worktreeRootURL.appending(path: ".git"),
            gitCommonDirectoryURL: worktreeRootURL.appending(path: ".git"),
            worktreeKind: worktreeKind,
            worktreeRootURLs: worktreeRootURLs ?? [worktreeRootURL],
            isRuriStyleWorktree: isRuriStyleWorktree,
            localBranches: localBranches,
            branch: branch,
            changesByURL: [:],
            diffsByURL: [:]
        )
    }
}
