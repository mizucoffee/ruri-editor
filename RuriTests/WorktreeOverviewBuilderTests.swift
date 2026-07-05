//
//  WorktreeOverviewBuilderTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class WorktreeOverviewBuilderTests: XCTestCase {
    func testItemsListWorktreesAndAttachTerminals() {
        let firstRootURL = URL(filePath: "/tmp/First")
        let secondRootURL = URL(filePath: "/tmp/Second")
        let firstTab = TerminalTab(defaultTitle: "First Terminal", cwd: firstRootURL, shellPath: "/bin/zsh").snapshot()
        let secondTerminal = TerminalTab(defaultTitle: "Second Terminal", cwd: secondRootURL, shellPath: "/bin/zsh")
        let agentStatus = CodingAgentStatus(
            terminalID: secondTerminal.id,
            provider: .codex,
            state: .running,
            event: "PreToolUse",
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            workspaceRoot: secondRootURL
        )
        let secondTab = secondTerminal.snapshot(
            agentStatus: CodingAgentTerminalStatus(status: agentStatus, isUnread: false)
        )
        let pullRequest = GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open
        )

        let items = WorktreeOverviewBuilder.items(
            projectWorkspaces: [
                ProjectWorkspaceSnapshot(id: firstRootURL, url: firstRootURL),
                ProjectWorkspaceSnapshot(id: secondRootURL, url: secondRootURL)
            ],
            terminalWorkspaces: [
                TerminalWorkspaceSnapshot(
                    id: firstRootURL,
                    rootURL: firstRootURL,
                    tabs: [firstTab],
                    selectedTabID: firstTab.id
                ),
                TerminalWorkspaceSnapshot(
                    id: secondRootURL,
                    rootURL: secondRootURL,
                    tabs: [secondTab],
                    selectedTabID: secondTab.id
                )
            ],
            branchStates: [
                firstRootURL.standardizedFileURL: .branch("main"),
                secondRootURL.standardizedFileURL: .branch("feature/sidebar")
            ],
            memos: [
                secondRootURL.standardizedFileURL: "Review sidebar"
            ],
            pullRequestStatuses: [
                secondRootURL.standardizedFileURL: .pullRequest(pullRequest)
            ],
            pullRequestLoadingWorkspaceIDs: [],
            pullingWorkspaceIDs: [],
            activeWorkspaceID: secondRootURL.standardizedFileURL,
            selectedTerminalTabID: secondTab.id,
            deletableWorkspaceIDs: [secondRootURL.standardizedFileURL]
        )

        XCTAssertEqual(items.map(\.id), [
            firstRootURL.standardizedFileURL,
            secondRootURL.standardizedFileURL
        ])
        XCTAssertEqual(items.map(\.branchTitle), ["main", "feature/sidebar"])
        XCTAssertFalse(items[0].isActive)
        XCTAssertTrue(items[1].isActive)
        XCTAssertEqual(items[1].memo, "Review sidebar")
        XCTAssertEqual(items[1].pullRequestStatus, .pullRequest(pullRequest))
        XCTAssertEqual(items[1].terminals.map(\.id), [secondTab.id])
        XCTAssertTrue(items[1].terminals[0].isSelected)
        XCTAssertEqual(items[1].terminals[0].tab.agentStatus?.status, agentStatus)
        XCTAssertTrue(items[1].canDelete)
    }

    func testDetachedBranchDisablesMemoEditing() {
        let rootURL = URL(filePath: "/tmp/Detached")

        let items = WorktreeOverviewBuilder.items(
            projectWorkspaces: [
                ProjectWorkspaceSnapshot(id: rootURL, url: rootURL)
            ],
            terminalWorkspaces: [],
            branchStates: [
                rootURL.standardizedFileURL: .detached("abc1234")
            ],
            memos: [:],
            pullRequestStatuses: [:],
            pullRequestLoadingWorkspaceIDs: [],
            pullingWorkspaceIDs: [],
            activeWorkspaceID: rootURL.standardizedFileURL,
            selectedTerminalTabID: nil,
            deletableWorkspaceIDs: []
        )

        XCTAssertEqual(items.first?.branchTitle, "abc1234")
        XCTAssertEqual(items.first?.canEditMemo, false)
    }

    func testRuriBaseIsAlwaysFirstAndOtherWorktreesAreSortedAlphabetically() {
        let projectURL = URL(filePath: "/tmp/RuriProject")
        let baseURL = projectURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        let alphaURL = projectURL.appending(path: "alpha", directoryHint: .isDirectory)
        let betaURL = projectURL.appending(path: "beta", directoryHint: .isDirectory)

        let items = WorktreeOverviewBuilder.items(
            projectWorkspaces: [
                ProjectWorkspaceSnapshot(id: betaURL, url: betaURL),
                ProjectWorkspaceSnapshot(id: baseURL, url: baseURL),
                ProjectWorkspaceSnapshot(id: alphaURL, url: alphaURL)
            ],
            terminalWorkspaces: [],
            branchStates: [
                betaURL.standardizedFileURL: .branch("beta"),
                alphaURL.standardizedFileURL: .branch("alpha"),
                baseURL.standardizedFileURL: .branch("main")
            ],
            memos: [:],
            pullRequestStatuses: [:],
            pullRequestLoadingWorkspaceIDs: [],
            pullingWorkspaceIDs: [],
            activeWorkspaceID: betaURL.standardizedFileURL,
            selectedTerminalTabID: nil,
            deletableWorkspaceIDs: [alphaURL.standardizedFileURL, betaURL.standardizedFileURL]
        )

        XCTAssertEqual(items.map(\.id), [
            baseURL.standardizedFileURL,
            alphaURL.standardizedFileURL,
            betaURL.standardizedFileURL
        ])
    }

    func testPullRequestLoadingFlagIsAttachedToWorkspace() {
        let rootURL = URL(filePath: "/tmp/Loading")

        let items = WorktreeOverviewBuilder.items(
            projectWorkspaces: [
                ProjectWorkspaceSnapshot(id: rootURL, url: rootURL)
            ],
            terminalWorkspaces: [],
            branchStates: [
                rootURL.standardizedFileURL: .branch("feature/loading")
            ],
            memos: [:],
            pullRequestStatuses: [:],
            pullRequestLoadingWorkspaceIDs: [rootURL.standardizedFileURL],
            pullingWorkspaceIDs: [],
            activeWorkspaceID: rootURL.standardizedFileURL,
            selectedTerminalTabID: nil,
            deletableWorkspaceIDs: [rootURL.standardizedFileURL]
        )

        XCTAssertEqual(items.first?.isPullRequestLoading, true)
        XCTAssertNil(items.first?.pullRequestStatus)
    }

    func testPullingFlagIsAttachedOnlyToPullingWorkspace() {
        let pullingURL = URL(filePath: "/tmp/Pulling")
        let idleURL = URL(filePath: "/tmp/Idle")

        let items = WorktreeOverviewBuilder.items(
            projectWorkspaces: [
                ProjectWorkspaceSnapshot(id: pullingURL, url: pullingURL),
                ProjectWorkspaceSnapshot(id: idleURL, url: idleURL)
            ],
            terminalWorkspaces: [],
            branchStates: [
                pullingURL.standardizedFileURL: .branch("main"),
                idleURL.standardizedFileURL: .branch("feature/idle")
            ],
            memos: [:],
            pullRequestStatuses: [:],
            pullRequestLoadingWorkspaceIDs: [],
            pullingWorkspaceIDs: [pullingURL.standardizedFileURL],
            activeWorkspaceID: pullingURL.standardizedFileURL,
            selectedTerminalTabID: nil,
            deletableWorkspaceIDs: []
        )

        XCTAssertEqual(items.first { $0.id == pullingURL.standardizedFileURL }?.isPulling, true)
        XCTAssertEqual(items.first { $0.id == idleURL.standardizedFileURL }?.isPulling, false)
    }

    func testCopyableBranchNameIsProvidedOnlyForRealBranches() {
        XCTAssertEqual(makeItem(branch: .branch("main")).copyableBranchName, "main")
        XCTAssertEqual(makeItem(branch: .unborn("feature/x")).copyableBranchName, "feature/x")
        XCTAssertNil(makeItem(branch: .detached("abc1234")).copyableBranchName)
        XCTAssertNil(makeItem(branch: nil).copyableBranchName)
    }

    func testCopyablePullRequestURLIsProvidedOnlyForExistingPullRequests() {
        let pullRequestURL = URL(string: "https://github.com/owner/repo/pull/42")!
        let pullRequest = GitHubPullRequestInfo(
            number: 42,
            url: pullRequestURL,
            lifecycleState: .open
        )
        let creationLink = GitHubPullRequestCreationLink(
            baseBranch: "main",
            headBranch: "feature/x",
            url: URL(string: "https://github.com/owner/repo/compare/main...feature/x")!
        )

        XCTAssertEqual(
            makeItem(pullRequestStatus: .pullRequest(pullRequest)).copyablePullRequestURL,
            pullRequestURL
        )
        XCTAssertNil(makeItem(pullRequestStatus: .create(creationLink)).copyablePullRequestURL)
        XCTAssertNil(makeItem(pullRequestStatus: nil).copyablePullRequestURL)
    }

    private func makeItem(
        branch: GitBranchState? = .branch("main"),
        pullRequestStatus: GitHubPullRequestStatus? = nil
    ) -> WorktreeOverviewItem {
        let rootURL = URL(filePath: "/tmp/Item")
        return WorktreeOverviewItem(
            workspace: ProjectWorkspaceSnapshot(id: rootURL, url: rootURL),
            branch: branch,
            memo: "",
            pullRequestStatus: pullRequestStatus,
            isPullRequestLoading: false,
            isPulling: false,
            terminals: [],
            isActive: false,
            canDelete: false
        )
    }
}
