//
//  EditorStateWorkspaceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorStateWorkspaceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testOpenProjectRequiresNewWindowForDifferentFolder() async throws {
        let firstRootURL = try makeTemporaryDirectory()
        let secondRootURL = try makeTemporaryDirectory()
        defer {
            try? fileManager.removeItem(at: firstRootURL)
            try? fileManager.removeItem(at: secondRootURL)
        }

        let editor = EditorState()

        let firstResult = await editor.openProject(firstRootURL)
        let secondResult = await editor.openProject(secondRootURL)

        XCTAssertEqual(firstResult, .opened(firstRootURL.standardizedFileURL))
        XCTAssertEqual(secondResult, .requiresNewWindow(secondRootURL.standardizedFileURL))
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [firstRootURL.standardizedFileURL])
        XCTAssertEqual(editor.activeProjectID, firstRootURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, firstRootURL.standardizedFileURL)
    }

    func testOpeningExistingProjectSelectsWithoutDuplicatingWorkspace() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let editor = EditorState()

        await editor.openProject(rootURL)
        let result = await editor.openProject(rootURL)

        XCTAssertEqual(result, .activated(rootURL.standardizedFileURL))
        XCTAssertEqual(editor.projectWorkspaces.count, 1)
        XCTAssertEqual(editor.activeProjectID, rootURL.standardizedFileURL)
    }

    func testProjectNameUsesOwnDirectoryForRegularProject() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "RegularProject", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)

        XCTAssertEqual(editor.projectName, "RegularProject")
    }

    func testProjectNameUsesParentDirectoryForRuriBaseProject() async throws {
        let parentURL = try makeTemporaryDirectory()
        let projectParentURL = parentURL.appending(path: "RuriProject", directoryHint: .isDirectory)
        let rootURL = projectParentURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)

        XCTAssertEqual(editor.projectName, "RuriProject")
    }

    func testProjectNameUsesRuriBaseParentForRuriStyleLinkedWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let projectParentURL = parentURL.appending(path: "RuriProject", directoryHint: .isDirectory)
        let baseURL = projectParentURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = projectParentURL.appending(path: "feature-sidebar", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let gitCommonDirectoryURL = baseURL
            .appending(path: ".git", directoryHint: .isDirectory)
            .standardizedFileURL
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature/sidebar"), headRevision: nil, kind: .linked)
        ]
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    worktreeURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: worktreeURL,
                        branch: .branch("feature/sidebar"),
                        worktreeKind: .linked,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        gitCommonDirectoryURL: gitCommonDirectoryURL
                    )
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(worktreeURL)

        XCTAssertEqual(editor.projectName, "RuriProject")
    }

    func testReviewModeStaysUnavailableForRegularProject() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)

        XCTAssertFalse(editor.canUseReviewMode)
        XCTAssertEqual(editor.editorMode, .edit)
        XCTAssertEqual(editor.reviewDiffState, .unavailable)
    }

    func testReviewModeLoadsRegularGitRepositoryDiffAgainstUncommittedBaseByDefault() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: []
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: repositorySnapshot
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ],
                expectedReviewBases: [
                    rootURL.standardizedFileURL: .uncommitted
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        let loadedSnapshot = try await waitForReviewDiffLoaded(editor)

        XCTAssertTrue(editor.canUseReviewMode)
        XCTAssertEqual(editor.editorMode, .review)
        XCTAssertEqual(editor.reviewDiffBase, .uncommitted)
        XCTAssertEqual(loadedSnapshot.base, .uncommitted)
        XCTAssertEqual(loadedSnapshot.targetBranch.displayName, currentBranch)
        XCTAssertTrue(FileURLRewriter.urlsMatch(loadedSnapshot.targetWorktreeRootURL, rootURL))
    }

    func testReviewDiffHideWhitespaceRefreshesDiffWithOption() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: []
        )
        let gitService = EditorStateWorkspaceMockGitService(
            snapshots: [
                rootURL.standardizedFileURL: repositorySnapshot
            ],
            reviewDiffs: [
                rootURL.standardizedFileURL: reviewSnapshot
            ]
        )
        let editor = EditorState(
            gitService: gitService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        editor.setReviewDiffHideWhitespace(true)
        _ = try await waitForReviewDiffCallCount(2, in: gitService)

        XCTAssertTrue(editor.reviewDiffHideWhitespace)
        XCTAssertEqual(gitService.reviewDiffCalls().map(\.options), [
            .default,
            GitReviewDiffOptions(hideWhitespace: true)
        ])
    }

    func testReviewDiffUsesFileScopedUpdateForExternalFileChange() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let changedURL = rootURL.appending(path: "Changed.kt")
        try "fun changed() = 2\n".write(to: changedURL, atomically: true, encoding: .utf8)

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let initialFile = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: "Changed.kt",
            newRelativePath: "Changed.kt",
            hunks: [
                SourceDiffHunk(
                    oldStart: 1,
                    oldLineCount: 1,
                    newStart: 1,
                    newLineCount: 1,
                    lines: [
                        SourceDiffLine(kind: .deletion, oldLineNumber: 1, newLineNumber: nil, content: "fun changed() = 1"),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, content: "fun changed() = old")
                    ]
                )
            ]
        ))
        let updatedFile = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: "Changed.kt",
            newRelativePath: "Changed.kt",
            hunks: [
                SourceDiffHunk(
                    oldStart: 1,
                    oldLineCount: 1,
                    newStart: 1,
                    newLineCount: 1,
                    lines: [
                        SourceDiffLine(kind: .deletion, oldLineNumber: 1, newLineNumber: nil, content: "fun changed() = 1"),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, content: "fun changed() = 2")
                    ]
                )
            ]
        ))
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [initialFile]
        )
        let reviewUpdate = GitReviewDiffUpdate(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            requestedRelativePaths: ["Changed.kt"],
            files: [updatedFile]
        )
        let gitService = EditorStateWorkspaceMockGitService(
            snapshots: [
                rootURL.standardizedFileURL: repositorySnapshot
            ],
            fileSnapshots: [
                changedURL.standardizedFileURL: GitFileSnapshot(
                    url: changedURL,
                    change: GitFileChange(
                        url: changedURL,
                        relativePath: "Changed.kt",
                        worktreeStatus: "M"
                    ),
                    diff: updatedFile.diff
                )
            ],
            reviewDiffs: [
                rootURL.standardizedFileURL: reviewSnapshot
            ],
            reviewDiffUpdates: [
                rootURL.standardizedFileURL: reviewUpdate
            ]
        )
        let editor = EditorState(
            gitService: gitService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        await editor.handleExternalProjectChange(ProjectFileWatcher.Change(
            rootURL: rootURL.standardizedFileURL,
            changedPaths: [changedURL.path(percentEncoded: false)],
            gitMetadataChangedPaths: []
        ))

        let loadedSnapshot = try await waitForReviewDiffLoaded(editor)

        XCTAssertEqual(gitService.reviewDiffCalls().count, 1)
        XCTAssertEqual(gitService.reviewDiffUpdateCalls(), [
            EditorStateWorkspaceMockGitService.ReviewDiffUpdateCall(
                base: .uncommitted,
                options: .default,
                fileURLs: [changedURL.standardizedFileURL],
                openedRootURL: rootURL.standardizedFileURL
            )
        ])
        XCTAssertTrue(loadedSnapshot.files[0].diff.hunks.flatMap(\.lines).contains { $0.content == "fun changed() = 2" })
    }

    func testOpenFileSwitchesFromReviewModeToEditMode() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Sources/Feature.swift")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let currentBranch = "feature/local"
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: []
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch(currentBranch)
                    )
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        await editor.openFile(fileURL)

        XCTAssertEqual(editor.editorMode, .edit)
        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.mainTabs.first { $0.id == selectedTabID })
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, fileURL))
    }

    func testReviewModeUsesSelectedReviewBase() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .branch("origin/main"),
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: []
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: repositorySnapshot
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ],
                expectedReviewBases: [
                    rootURL.standardizedFileURL: .branch("origin/main")
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setReviewDiffBase(.branch("origin/main"))
        editor.setEditorMode(.review)
        let loadedSnapshot = try await waitForReviewDiffLoaded(editor)

        XCTAssertEqual(editor.reviewDiffBase, .branch("origin/main"))
        XCTAssertEqual(loadedSnapshot.base, .branch("origin/main"))
    }

    func testReviewBaseSelectionPersistsPerBranch() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let gitService = EditorStateWorkspaceMockGitService(
            snapshots: [
                rootURL.standardizedFileURL: repositorySnapshot
            ]
        )
        let firstEditor = EditorState(
            gitService: gitService,
            isFileWatchingEnabled: false
        )

        await firstEditor.openProject(rootURL)
        firstEditor.setReviewDiffBase(.branch("origin/main"))
        try await waitForStoredReviewBase(
            .branch("origin/main"),
            branchName: currentBranch,
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        )

        let secondEditor = EditorState(
            gitService: gitService,
            isFileWatchingEnabled: false
        )

        await secondEditor.openProject(rootURL)
        try await waitForReviewBase(secondEditor, .branch("origin/main"))
    }

    func testActivatingFileTreeFileInReviewModeSwitchesToEditMode() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Feature.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            baseBranch: currentBranch,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            mergeBaseRevision: "abc123",
            files: []
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: repositorySnapshot
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        editor.selectFileTreeNode(fileURL)
        let closedDocument = await editor.activateSelectedFileTreeNode()

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.editorMode, .edit)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, fileURL))
    }

    func testNavigateToFileRangeInReviewModeSwitchesToEditMode() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Feature.swift")
        let text = "let value = 1\nlet target = value\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let currentBranch = "feature/local"
        let repositorySnapshot = makeGitSnapshot(
            rootURL: rootURL,
            branch: .branch(currentBranch)
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            baseBranch: currentBranch,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            mergeBaseRevision: "abc123",
            files: []
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: repositorySnapshot
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        let targetRange = (text as NSString).range(of: "target")
        let closedDocument = await editor.navigateToFileRange(fileURL, range: targetRange)

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.editorMode, .edit)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, fileURL))

        let session = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, targetRange))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    func testSwitchGitBranchUpdatesActiveRuriBaseWorkspaceGitState() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "main\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "main"], in: rootURL)
        try runGit(["switch", "-c", "feature/sidebar"], in: rootURL)
        try "feature\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "feature"], in: rootURL)
        try runGit(["switch", "main"], in: rootURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        XCTAssertEqual(editor.gitSnapshot?.branch.displayName, "main")

        try await editor.switchGitBranch(named: "feature/sidebar")

        XCTAssertEqual(editor.gitSnapshot?.branch.displayName, "feature/sidebar")
        XCTAssertEqual(editor.projectName, "RuriProject")
        XCTAssertEqual(
            try String(contentsOf: rootURL.appending(path: "Tracked.txt"), encoding: .utf8),
            "feature\n"
        )
    }

    func testOpeningMainWorktreeLoadsLinkedWorktreesInSameWindow() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "tracked\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        try runGit(["worktree", "add", "-b", "linked", worktreeURL.path(percentEncoded: false)], in: rootURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        let result = await editor.openProject(rootURL)

        XCTAssertEqual(result, .opened(rootURL.standardizedFileURL))
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [
            rootURL.standardizedFileURL,
            worktreeURL.standardizedFileURL
        ])
        XCTAssertEqual(editor.projectWorkspaces.map(\.displayName), ["main", "linked"])
        XCTAssertEqual(editor.activeProjectID, rootURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, rootURL.standardizedFileURL)

        editor.selectProject(worktreeURL.standardizedFileURL)

        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, worktreeURL.standardizedFileURL)
    }

    func testGitBranchesByProjectIDTracksOpenedWorkspaces() async throws {
        let parentURL = try makeTemporaryDirectory()
        let firstRootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let secondRootURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: firstRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondRootURL, withIntermediateDirectories: true)

        let worktrees = [
            GitWorktreeInfo(rootURL: firstRootURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: secondRootURL, branch: .branch("feature/sidebar"), headRevision: nil, kind: .linked)
        ]
        let worktreeRootURLs = [firstRootURL, secondRootURL]
        let firstSnapshot = makeGitSnapshot(
            rootURL: firstRootURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: worktreeRootURLs,
            worktrees: worktrees
        )
        let secondSnapshot = makeGitSnapshot(
            rootURL: secondRootURL,
            branch: .branch("feature/sidebar"),
            worktreeKind: .linked,
            worktreeRootURLs: worktreeRootURLs,
            worktrees: worktrees
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    firstRootURL.standardizedFileURL: firstSnapshot,
                    secondRootURL.standardizedFileURL: secondSnapshot
                ]
            ),
            isFileWatchingEnabled: false
        )

        let result = await editor.openProject(firstRootURL)

        XCTAssertEqual(result, .opened(firstRootURL.standardizedFileURL))
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [
            firstRootURL.standardizedFileURL,
            secondRootURL.standardizedFileURL
        ])
        XCTAssertEqual(editor.gitBranchesByProjectID[firstRootURL.standardizedFileURL]?.displayName, "main")
        XCTAssertEqual(editor.gitBranchesByProjectID[secondRootURL.standardizedFileURL]?.displayName, "feature/sidebar")
        XCTAssertEqual(editor.gitSnapshot?.branch.displayName, "main")

        editor.selectProject(secondRootURL.standardizedFileURL)

        XCTAssertEqual(editor.gitSnapshot?.branch.displayName, "feature/sidebar")
    }

    func testOpeningBranchWorkspacePublishesGitHubPullRequest() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let pullRequest = GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open
        )
        let gitHubPullRequestService = EditorStateWorkspaceMockGitHubPullRequestService(pullRequests: [
            rootURL.standardizedFileURL: [
                "feature/status-pr": .pullRequest(pullRequest)
            ]
        ])
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch("feature/status-pr")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        let publishedPullRequest = try await waitForGitHubPullRequestStatus(editor)

        XCTAssertEqual(publishedPullRequest, .pullRequest(pullRequest))
        let calls = await gitHubPullRequestService.calls()
        XCTAssertEqual(calls, [
            EditorStateWorkspaceMockGitHubPullRequestService.Call(
                branchName: "feature/status-pr",
                baseBranchName: nil,
                openedRootURL: rootURL.standardizedFileURL
            )
        ])
    }

    func testGitHubPullRequestFollowsActiveWorkspace() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let baseSnapshot = makeGitSnapshot(
            rootURL: baseURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            isRuriStyleWorktree: true,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let worktreeSnapshot = makeGitSnapshot(
            rootURL: worktreeURL,
            branch: .branch("feature-one"),
            worktreeKind: .linked,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let pullRequest = GitHubPullRequestInfo(
            number: 77,
            url: URL(string: "https://github.com/owner/repo/pull/77")!,
            lifecycleState: .open
        )
        let gitHubPullRequestService = EditorStateWorkspaceMockGitHubPullRequestService(pullRequests: [
            worktreeURL.standardizedFileURL: [
                "feature-one": .pullRequest(pullRequest)
            ]
        ])
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: baseSnapshot,
                    worktreeURL.standardizedFileURL: worktreeSnapshot
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        XCTAssertNil(editor.githubPullRequestStatus)

        let call = try await waitForGitHubPullRequestCall(
            gitHubPullRequestService,
            branchName: "feature-one",
            baseBranchName: "main",
            openedRootURL: worktreeURL.standardizedFileURL
        )
        XCTAssertEqual(call.baseBranchName, "main")
        try await waitForGitHubPullRequestStatus(
            editor,
            workspaceID: worktreeURL.standardizedFileURL,
            expectedStatus: .pullRequest(pullRequest)
        )

        editor.selectProject(worktreeURL.standardizedFileURL)
        let activePullRequest = try await waitForGitHubPullRequestStatus(editor)

        XCTAssertEqual(activePullRequest, .pullRequest(pullRequest))
    }

    func testGitHubPullRequestPublishesCreationLinkForLinkedWorktreeWithoutPullRequest() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("develop"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let creationLink = GitHubPullRequestCreationLink(
            baseBranch: "develop",
            headBranch: "feature-one",
            url: URL(string: "https://github.com/owner/repo/compare/develop...feature-one?expand=1")!
        )
        let gitHubPullRequestService = EditorStateWorkspaceMockGitHubPullRequestService(pullRequests: [
            worktreeURL.standardizedFileURL: [
                "feature-one": .create(creationLink)
            ]
        ])
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: baseURL,
                        branch: .branch("develop"),
                        worktreeKind: .main,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        isRuriStyleWorktree: true,
                        gitCommonDirectoryURL: commonGitDirectoryURL
                    ),
                    worktreeURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: worktreeURL,
                        branch: .branch("feature-one"),
                        worktreeKind: .linked,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        gitCommonDirectoryURL: commonGitDirectoryURL
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        editor.selectProject(worktreeURL.standardizedFileURL)

        let status = try await waitForGitHubPullRequestStatus(editor)
        XCTAssertEqual(status, .create(creationLink))
        let call = try await waitForGitHubPullRequestCall(
            gitHubPullRequestService,
            branchName: "feature-one",
            baseBranchName: "develop",
            openedRootURL: worktreeURL.standardizedFileURL
        )
        XCTAssertEqual(call.baseBranchName, "develop")
    }

    func testGitHubPullRequestLoadingStateClearsWhenNoPullRequestIsFound() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-loading", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-loading"), headRevision: nil, kind: .linked)
        ]
        let gitHubPullRequestService = EditorStateWorkspaceMockGitHubPullRequestService(
            pullRequests: [:],
            responseDelayNanoseconds: 300_000_000
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: baseURL,
                        branch: .branch("main"),
                        worktreeKind: .main,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        isRuriStyleWorktree: true,
                        gitCommonDirectoryURL: commonGitDirectoryURL
                    ),
                    worktreeURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: worktreeURL,
                        branch: .branch("feature-loading"),
                        worktreeKind: .linked,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        gitCommonDirectoryURL: commonGitDirectoryURL
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        _ = try await waitForGitHubPullRequestCall(
            gitHubPullRequestService,
            branchName: "feature-loading",
            baseBranchName: "main",
            openedRootURL: worktreeURL.standardizedFileURL
        )
        try await waitForGitHubPullRequestLoadingState(
            editor,
            workspaceID: worktreeURL.standardizedFileURL,
            isLoading: true
        )
        try await waitForGitHubPullRequestLoadingState(
            editor,
            workspaceID: worktreeURL.standardizedFileURL,
            isLoading: false
        )

        XCTAssertNil(editor.githubPullRequestStatusesByProjectID[worktreeURL.standardizedFileURL])
    }

    func testDetachedWorkspaceDoesNotRequestGitHubPullRequest() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let gitHubPullRequestService = EditorStateWorkspaceMockGitHubPullRequestService(pullRequests: [:])
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .detached("abc1234")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)

        XCTAssertNil(editor.githubPullRequestStatus)
        let calls = await gitHubPullRequestService.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testExternalPullRequestURLSelectsExistingWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "feature-status-pr", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let gitCommonDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature/status-pr"), headRevision: nil, kind: .linked)
        ]
        let pullRequestDetails = GitHubPullRequestDetails(
            number: 123,
            url: URL(string: "https://github.com/owner/repo/pull/123")!,
            state: "OPEN",
            headBranchName: "feature/status-pr",
            baseBranchName: "main",
            headRepository: GitHubRepositoryIdentity(owner: "owner", name: "repo")
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: baseURL,
                        branch: .branch("main"),
                        worktreeKind: .main,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        gitCommonDirectoryURL: gitCommonDirectoryURL
                    ),
                    worktreeURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: worktreeURL,
                        branch: .branch("feature/status-pr"),
                        worktreeKind: .linked,
                        worktreeRootURLs: [baseURL, worktreeURL],
                        worktrees: worktrees,
                        gitCommonDirectoryURL: gitCommonDirectoryURL
                    )
                ],
                reviewDiffs: [
                    worktreeURL.standardizedFileURL: GitReviewDiffSnapshot(
                        base: .uncommitted,
                        targetBranch: .branch("feature/status-pr"),
                        targetWorktreeRootURL: worktreeURL,
                        baseRevision: "abc123",
                        files: []
                    )
                ],
                githubRepositoryIdentitiesByRoot: [
                    baseURL.standardizedFileURL: [GitHubRepositoryIdentity(owner: "owner", name: "repo")]
                ]
            ),
            githubPullRequestService: EditorStateWorkspaceMockGitHubPullRequestService(
                pullRequests: [:],
                pullRequestDetailsByRootAndNumber: [
                    baseURL.standardizedFileURL: [123: pullRequestDetails]
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        await editor.openExternalGitHubPullRequestURL(URL(string: "ruri://github.com/owner/repo/pull/123")!)

        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.editorMode, .review)
        XCTAssertNil(editor.externalPullRequestWorktreeCreationRequest)
    }

    func testExternalPullRequestURLRequestsWorktreeCreationWhenMissing() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let pullRequestDetails = GitHubPullRequestDetails(
            number: 123,
            url: URL(string: "https://github.com/owner/repo/pull/123")!,
            state: "OPEN",
            headBranchName: "feature/status-pr",
            baseBranchName: "main",
            headRepository: GitHubRepositoryIdentity(owner: "owner", name: "repo")
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch("main"))
                ],
                githubRepositoryIdentitiesByRoot: [
                    rootURL.standardizedFileURL: [GitHubRepositoryIdentity(owner: "owner", name: "repo")]
                ]
            ),
            githubPullRequestService: EditorStateWorkspaceMockGitHubPullRequestService(
                pullRequests: [:],
                pullRequestDetailsByRootAndNumber: [
                    rootURL.standardizedFileURL: [123: pullRequestDetails]
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        await editor.openExternalGitHubPullRequestURL(URL(string: "ruri://github.com/owner/repo/pull/123")!)

        XCTAssertEqual(
            editor.externalPullRequestWorktreeCreationRequest?.remoteBranchName,
            "origin/feature/status-pr"
        )
        XCTAssertEqual(editor.activeProjectID, rootURL.standardizedFileURL)
    }

    func testConfirmExternalPullRequestWorktreeCreationUsesCapturedRequest() async throws {
        let parentURL = try makeTemporaryDirectory()
        let remoteURL = parentURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let seedURL = parentURL.appending(path: "seed", directoryHint: .isDirectory)
        let projectURL = parentURL.appending(path: "Project", directoryHint: .isDirectory)
        let rootURL = projectURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = projectURL.appending(path: "feature", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: seedURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try runGit(["init", "--bare", "-b", "main", remoteURL.path(percentEncoded: false)], in: parentURL)
        try initializeRepository(at: seedURL)
        try "base\n".write(to: seedURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: seedURL)
        try runGit(["commit", "-m", "base"], in: seedURL)
        try runGit(["remote", "add", "origin", remoteURL.path(percentEncoded: false)], in: seedURL)
        try runGit(["push", "-u", "origin", "main"], in: seedURL)
        try runGit(["clone", remoteURL.path(percentEncoded: false), rootURL.path(percentEncoded: false)], in: projectURL)
        try runGit(["config", "user.email", "test@example.com"], in: rootURL)
        try runGit(["config", "user.name", "Test"], in: rootURL)
        try runGit(["switch", "-c", "feature"], in: seedURL)
        try "remote branch\n".write(to: seedURL.appending(path: "RemoteBranch.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "RemoteBranch.txt"], in: seedURL)
        try runGit(["commit", "-m", "remote branch"], in: seedURL)
        try runGit(["push", "-u", "origin", "feature"], in: seedURL)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        let request = ExternalPullRequestWorktreeCreationRequest(
            pullRequestNumber: 1,
            repository: GitHubRepositoryIdentity(owner: "owner", name: "repo"),
            headBranchName: "feature",
            remoteBranchName: "origin/feature",
            sourceWorkspaceID: rootURL
        )

        await editor.confirmExternalPullRequestWorktreeCreation(request)

        XCTAssertNil(editor.externalPullRequestWorktreeCreationRequest)
        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.editorMode, .review)
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.appending(path: "RemoteBranch.txt").path(percentEncoded: false)))
    }

    func testContentChangeRefreshesOnlyChangedWorktreeGitState() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let baseSnapshot = makeGitSnapshot(
            rootURL: baseURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            isRuriStyleWorktree: true,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let worktreeSnapshot = makeGitSnapshot(
            rootURL: worktreeURL,
            branch: .branch("feature-one"),
            worktreeKind: .linked,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            gitDirectoryURL: commonGitDirectoryURL
                .appending(path: "worktrees/feature-one", directoryHint: .isDirectory),
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let gitService = RecordingEditorStateWorkspaceGitService(snapshots: [
            baseURL.standardizedFileURL: baseSnapshot,
            worktreeURL.standardizedFileURL: worktreeSnapshot
        ])
        let editor = EditorState(gitService: gitService, isFileWatchingEnabled: false)

        await editor.openProject(baseURL)
        gitService.resetRepositoryStatusURLs()

        let changedFileURL = worktreeURL.appending(path: "Changed.kt")
        await editor.handleExternalProjectChange(ProjectFileWatcher.Change(
            rootURL: worktreeURL.standardizedFileURL,
            changedPaths: [changedFileURL.path(percentEncoded: false)],
            gitMetadataChangedPaths: []
        ))

        XCTAssertEqual(gitService.repositoryStatusURLs(), [worktreeURL.standardizedFileURL])
        XCTAssertEqual(editor.fileChangeNotification?.projectURL, worktreeURL.standardizedFileURL)
    }

    func testLinkedWorktreeGitMetadataRefreshesOnlyLinkedWorktreeGitState() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let linkedGitDirectoryURL = commonGitDirectoryURL
            .appending(path: "worktrees/feature-one", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let baseSnapshot = makeGitSnapshot(
            rootURL: baseURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            isRuriStyleWorktree: true,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let worktreeSnapshot = makeGitSnapshot(
            rootURL: worktreeURL,
            branch: .branch("feature-one"),
            worktreeKind: .linked,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            gitDirectoryURL: linkedGitDirectoryURL,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let gitService = RecordingEditorStateWorkspaceGitService(snapshots: [
            baseURL.standardizedFileURL: baseSnapshot,
            worktreeURL.standardizedFileURL: worktreeSnapshot
        ])
        let editor = EditorState(gitService: gitService, isFileWatchingEnabled: false)

        await editor.openProject(baseURL)
        gitService.resetRepositoryStatusURLs()

        await editor.handleExternalProjectChange(ProjectFileWatcher.Change(
            rootURL: baseURL.standardizedFileURL,
            changedPaths: [],
            gitMetadataChangedPaths: [
                linkedGitDirectoryURL
                    .appending(path: "HEAD")
                    .path(percentEncoded: false)
            ]
        ))

        XCTAssertEqual(gitService.repositoryStatusURLs(), [worktreeURL.standardizedFileURL])
        XCTAssertNil(editor.fileChangeNotification)
    }

    func testReviewModeLoadsActiveWorkspaceDiffForRuriStyleWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let baseSnapshot = makeGitSnapshot(
            rootURL: baseURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            isRuriStyleWorktree: true,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let worktreeSnapshot = makeGitSnapshot(
            rootURL: worktreeURL,
            branch: .branch("feature-one"),
            worktreeKind: .linked,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            baseBranch: "main",
            targetBranch: .branch("feature-one"),
            targetWorktreeRootURL: worktreeURL,
            mergeBaseRevision: "abc123",
            files: []
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: baseSnapshot,
                    worktreeURL.standardizedFileURL: worktreeSnapshot
                ],
                reviewDiffs: [
                    worktreeURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        editor.selectProject(worktreeURL.standardizedFileURL)
        editor.setEditorMode(.review)
        let loadedSnapshot = try await waitForReviewDiffLoaded(editor)

        XCTAssertTrue(editor.canUseReviewMode)
        XCTAssertEqual(editor.editorMode, .review)
        XCTAssertEqual(loadedSnapshot.baseBranch, "main")
        XCTAssertEqual(loadedSnapshot.targetBranch.displayName, "feature-one")
        XCTAssertTrue(FileURLRewriter.urlsMatch(loadedSnapshot.targetWorktreeRootURL, worktreeURL))
    }

    func testReviewDiffCodeNavigationSwitchesToEditAndOpensImplementation() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let definitionURL = worktreeURL.appending(path: "Definition.kt")
        let usageURL = worktreeURL.appending(path: "Usage.kt")
        let definitionText = "class Target\n"
        let usageText = "fun main() { Target() }\n"
        try definitionText.write(to: definitionURL, atomically: true, encoding: .utf8)
        try usageText.write(to: usageURL, atomically: true, encoding: .utf8)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let baseSnapshot = makeGitSnapshot(
            rootURL: baseURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            isRuriStyleWorktree: true,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let worktreeSnapshot = makeGitSnapshot(
            rootURL: worktreeURL,
            branch: .branch("feature-one"),
            worktreeKind: .linked,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            baseBranch: "main",
            targetBranch: .branch("feature-one"),
            targetWorktreeRootURL: worktreeURL,
            mergeBaseRevision: "abc123",
            files: [
                GitReviewFileDiff(diff: SourceFileDiff(
                    oldRelativePath: "Usage.kt",
                    newRelativePath: "Usage.kt",
                    hunks: [
                        SourceDiffHunk(
                            oldStart: 1,
                            oldLineCount: 0,
                            newStart: 1,
                            newLineCount: 1,
                            lines: [
                                SourceDiffLine(
                                    kind: .addition,
                                    oldLineNumber: nil,
                                    newLineNumber: 1,
                                    content: String(usageText.dropLast())
                                )
                            ]
                        )
                    ]
                ))
            ]
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: baseSnapshot,
                    worktreeURL.standardizedFileURL: worktreeSnapshot
                ],
                reviewDiffs: [
                    worktreeURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        editor.selectProject(worktreeURL.standardizedFileURL)
        try await waitForSymbolIndexReady(editor)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        let targetColumn = (usageText as NSString).range(of: "Target").location
        let result = await editor.resolveReviewDiffImplementationOrReferences(
            ReviewDiffCodeNavigationRequest(
                fileURL: usageURL,
                lineNumber: 1,
                utf16Column: targetColumn
            )
        )

        guard case .navigated(let closedDocument) = result else {
            return XCTFail("Expected Review Diff code navigation to open the implementation.")
        }

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.editorMode, .edit)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, definitionURL))

        let definitionRange = (definitionText as NSString).range(of: "Target")
        let session = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, definitionRange))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    func testReviewDiffOldSideCodeNavigationUsesMergeBaseContents() async throws {
        let parentURL = try makeTemporaryDirectory()
        let baseURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "RuriProject", directoryHint: .isDirectory)
            .appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: worktreeURL, withIntermediateDirectories: true)

        let definitionURL = worktreeURL.appending(path: "Definition.kt")
        let usageURL = worktreeURL.appending(path: "Usage.kt")
        let definitionText = "class Target\n"
        let oldUsageText = "fun main() { Target() }\n"
        let currentUsageText = "fun main() { CurrentOnly() }\n"
        try definitionText.write(to: definitionURL, atomically: true, encoding: .utf8)
        try currentUsageText.write(to: usageURL, atomically: true, encoding: .utf8)

        let commonGitDirectoryURL = baseURL.appending(path: ".git", directoryHint: .isDirectory)
        let worktrees = [
            GitWorktreeInfo(rootURL: baseURL, branch: .branch("main"), headRevision: nil, kind: .main),
            GitWorktreeInfo(rootURL: worktreeURL, branch: .branch("feature-one"), headRevision: nil, kind: .linked)
        ]
        let baseSnapshot = makeGitSnapshot(
            rootURL: baseURL,
            branch: .branch("main"),
            worktreeKind: .main,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            isRuriStyleWorktree: true,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let worktreeSnapshot = makeGitSnapshot(
            rootURL: worktreeURL,
            branch: .branch("feature-one"),
            worktreeKind: .linked,
            worktreeRootURLs: [baseURL, worktreeURL],
            worktrees: worktrees,
            gitCommonDirectoryURL: commonGitDirectoryURL
        )
        let reviewSnapshot = GitReviewDiffSnapshot(
            baseBranch: "main",
            targetBranch: .branch("feature-one"),
            targetWorktreeRootURL: worktreeURL,
            mergeBaseRevision: "abc123",
            files: [
                GitReviewFileDiff(diff: SourceFileDiff(
                    oldRelativePath: "Usage.kt",
                    newRelativePath: "Usage.kt",
                    hunks: [
                        SourceDiffHunk(
                            oldStart: 1,
                            oldLineCount: 1,
                            newStart: 1,
                            newLineCount: 1,
                            lines: [
                                SourceDiffLine(
                                    kind: .deletion,
                                    oldLineNumber: 1,
                                    newLineNumber: nil,
                                    content: String(oldUsageText.dropLast())
                                ),
                                SourceDiffLine(
                                    kind: .addition,
                                    oldLineNumber: nil,
                                    newLineNumber: 1,
                                    content: String(currentUsageText.dropLast())
                                )
                            ]
                        )
                    ]
                ))
            ]
        )
        let editor = EditorState(
            gitService: EditorStateWorkspaceMockGitService(
                snapshots: [
                    baseURL.standardizedFileURL: baseSnapshot,
                    worktreeURL.standardizedFileURL: worktreeSnapshot
                ],
                reviewDiffs: [
                    worktreeURL.standardizedFileURL: reviewSnapshot
                ],
                fileContentsByRootAndRevision: [
                    worktreeURL.standardizedFileURL: [
                        "abc123": [
                            "Usage.kt": oldUsageText
                        ]
                    ]
                ]
            ),
            isFileWatchingEnabled: false
        )

        await editor.openProject(baseURL)
        editor.selectProject(worktreeURL.standardizedFileURL)
        try await waitForSymbolIndexReady(editor)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        let targetColumn = (oldUsageText as NSString).range(of: "Target").location
        let request = ReviewDiffCodeNavigationRequest(
            fileURL: usageURL,
            side: .old,
            lineNumber: 1,
            utf16Column: targetColumn
        )

        let hoverRange = await editor.reviewDiffImplementationHoverRange(request)
        XCTAssertTrue(NSEqualRanges(
            hoverRange ?? NSRange(location: NSNotFound, length: 0),
            NSRange(location: targetColumn, length: 6)
        ))

        let result = await editor.resolveReviewDiffImplementationOrReferences(request)

        guard case .navigated(let closedDocument) = result else {
            return XCTFail("Expected old-side Review Diff code navigation to open the implementation.")
        }

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.editorMode, .edit)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, definitionURL))

        let definitionRange = (definitionText as NSString).range(of: "Target")
        let session = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, definitionRange))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    func testReviewDiffCodeNavigationRequestMapsLineAndColumnToUTF16Offset() {
        let text = "first\nsecond\nemoji 😄 target\n"
        let thirdLineStart = ("first\nsecond\n" as NSString).length
        let thirdLineLength = ("emoji 😄 target" as NSString).length

        XCTAssertEqual(
            ReviewDiffCodeNavigationRequest.utf16Offset(lineNumber: 1, utf16Column: -5, in: text),
            0
        )
        XCTAssertEqual(
            ReviewDiffCodeNavigationRequest.utf16Offset(lineNumber: 2, utf16Column: 3, in: text),
            ("first\n" as NSString).length + 3
        )
        XCTAssertEqual(
            ReviewDiffCodeNavigationRequest.utf16Offset(lineNumber: 3, utf16Column: 999, in: text),
            thirdLineStart + thirdLineLength
        )
        XCTAssertNil(ReviewDiffCodeNavigationRequest.utf16Offset(lineNumber: 0, utf16Column: 0, in: text))
        XCTAssertNil(ReviewDiffCodeNavigationRequest.utf16Offset(lineNumber: 5, utf16Column: 0, in: text))
    }

    func testOpeningLinkedWorktreeDirectlyDoesNotLoadSiblingWorktrees() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "tracked\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        try runGit(["worktree", "add", "-b", "linked", worktreeURL.path(percentEncoded: false)], in: rootURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        let result = await editor.openProject(worktreeURL)

        XCTAssertEqual(result, .opened(worktreeURL.standardizedFileURL))
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [worktreeURL.standardizedFileURL])
        XCTAssertEqual(editor.projectWorkspaces.map(\.displayName), ["linked"])
        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
    }

    func testCreateWorktreeOpensCreatedWorktreeInSameWindow() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)
        try "head\n".write(to: rootURL.appending(path: "Head.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Head.txt"], in: rootURL)
        try runGit(["commit", "-m", "head"], in: rootURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        let workspaceID = try await editor.createWorktree(named: "feature-one")

        XCTAssertEqual(workspaceID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [
            rootURL.standardizedFileURL,
            worktreeURL.standardizedFileURL
        ])
        XCTAssertEqual(editor.projectWorkspaces.map(\.displayName), ["main", "feature-one"])
        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.gitBranchesByProjectID[worktreeURL.standardizedFileURL]?.displayName, "feature-one")
        XCTAssertEqual(editor.gitSnapshot?.branch.displayName, "feature-one")
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.appending(path: "Base.txt").path(percentEncoded: false)))
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.appending(path: "Head.txt").path(percentEncoded: false)))
    }

    func testCreateWorktreeFromLinkedWorkspaceUsesMainWorktreeHeadAsBase() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let linkedURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        let newWorktreeURL = parentURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)
        try runGit(["worktree", "add", "-b", "linked", linkedURL.path(percentEncoded: false)], in: rootURL)
        try "linked\n".write(to: linkedURL.appending(path: "LinkedOnly.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "LinkedOnly.txt"], in: linkedURL)
        try runGit(["commit", "-m", "linked only"], in: linkedURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        editor.selectProject(linkedURL.standardizedFileURL)
        _ = try await editor.createWorktree(named: "feature-one")

        XCTAssertEqual(editor.activeProjectID, newWorktreeURL.standardizedFileURL)
        XCTAssertTrue(fileManager.fileExists(atPath: newWorktreeURL.appending(path: "Base.txt").path(percentEncoded: false)))
        XCTAssertFalse(fileManager.fileExists(atPath: newWorktreeURL.appending(path: "LinkedOnly.txt").path(percentEncoded: false)))
    }

    func testCreateWorktreeFromRemoteBranchOpensCreatedWorktreeInSameWindow() async throws {
        let parentURL = try makeTemporaryDirectory()
        let projectURL = parentURL.appending(path: "Project", directoryHint: .isDirectory)
        let remoteURL = parentURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let seedURL = parentURL.appending(path: "seed", directoryHint: .isDirectory)
        let rootURL = projectURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = projectURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: seedURL, withIntermediateDirectories: true)
        try runGit(["init", "--bare", "-b", "main", remoteURL.path(percentEncoded: false)], in: parentURL)
        try initializeRepository(at: seedURL)
        try "base\n".write(to: seedURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: seedURL)
        try runGit(["commit", "-m", "base"], in: seedURL)
        try runGit(["remote", "add", "origin", remoteURL.path(percentEncoded: false)], in: seedURL)
        try runGit(["push", "-u", "origin", "main"], in: seedURL)
        try runGit(["clone", remoteURL.path(percentEncoded: false), rootURL.path(percentEncoded: false)], in: projectURL)
        try runGit(["config", "user.email", "test@example.com"], in: rootURL)
        try runGit(["config", "user.name", "Test"], in: rootURL)
        try runGit(["switch", "-c", "feature-one"], in: seedURL)
        try "remote branch\n".write(to: seedURL.appending(path: "RemoteBranch.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "RemoteBranch.txt"], in: seedURL)
        try runGit(["commit", "-m", "remote branch"], in: seedURL)
        try runGit(["push", "-u", "origin", "feature-one"], in: seedURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        let remoteBranches = try await editor.remoteBranches(refresh: true)
        let workspaceID = try await editor.createWorktree(fromRemoteBranch: "origin/feature-one")

        XCTAssertTrue(remoteBranches.contains(GitRemoteBranchInfo(fullName: "origin/feature-one")!))
        XCTAssertEqual(workspaceID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [
            rootURL.standardizedFileURL,
            worktreeURL.standardizedFileURL
        ])
        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.gitBranchesByProjectID[worktreeURL.standardizedFileURL]?.displayName, "feature-one")
        XCTAssertEqual(editor.gitSnapshot?.branch.displayName, "feature-one")
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.appending(path: "RemoteBranch.txt").path(percentEncoded: false)))
    }

    func testInitializeCreatedWorktreeRunsCommandInCreatedRoot() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        let initializationService = RecordingWorktreeInitializationService()
        let editor = EditorState(
            worktreeInitializationService: initializationService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        let workspaceID = try await editor.createWorktree(named: "feature-one")
        try await editor.initializeWorktree(workspaceID, command: "npm install")

        XCTAssertEqual(initializationService.calls(), [
            RecordingWorktreeInitializationService.Call(
                command: "npm install",
                worktreeRootURL: worktreeURL.standardizedFileURL
            )
        ])
        XCTAssertEqual(
            try String(contentsOf: worktreeURL.appending(path: "initialized.txt"), encoding: .utf8),
            "npm install\n"
        )
    }

    func testInitializeCreatedWorktreeFailureKeepsCreatedWorktreeActive() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        let initializationService = RecordingWorktreeInitializationService(
            error: WorktreeInitializationError.processFailed("boom")
        )
        let editor = EditorState(
            worktreeInitializationService: initializationService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        let workspaceID = try await editor.createWorktree(named: "feature-one")

        do {
            try await editor.initializeWorktree(workspaceID, command: "npm install")
            XCTFail("Expected initialization to fail.")
        } catch WorktreeInitializationError.processFailed(let message) {
            XCTAssertEqual(message, "boom")
        }

        XCTAssertEqual(editor.activeProjectID, worktreeURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, worktreeURL.standardizedFileURL)
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.path(percentEncoded: false)))
    }

    func testDeleteWorktreeRemovesWorkspaceAndSelectsMainWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let linkedURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)
        try runGit(["worktree", "add", "-b", "linked", linkedURL.path(percentEncoded: false)], in: rootURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        editor.selectProject(linkedURL.standardizedFileURL)
        XCTAssertTrue(editor.canDeleteWorktree)
        XCTAssertEqual(editor.activeWorktreeDeletionTarget?.displayName, "linked")

        let result = try await editor.deleteWorktree(linkedURL.standardizedFileURL)

        XCTAssertEqual(result.workspaceID, linkedURL.standardizedFileURL)
        XCTAssertEqual(result.activatedWorkspaceID, rootURL.standardizedFileURL)
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [rootURL.standardizedFileURL])
        XCTAssertEqual(editor.activeProjectID, rootURL.standardizedFileURL)
        XCTAssertEqual(editor.projectURL, rootURL.standardizedFileURL)
        XCTAssertFalse(editor.canDeleteWorktree)
        XCTAssertFalse(fileManager.fileExists(atPath: linkedURL.path(percentEncoded: false)))
        XCTAssertFalse(
            try runGit(["rev-parse", "--verify", "linked"], in: rootURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
    }

    func testDeleteOnlyOpenedLinkedWorktreeClearsProject() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let linkedURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)
        try runGit(["worktree", "add", "-b", "linked", linkedURL.path(percentEncoded: false)], in: rootURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(linkedURL)
        let result = try await editor.deleteWorktree(linkedURL.standardizedFileURL)

        XCTAssertEqual(result.workspaceID, linkedURL.standardizedFileURL)
        XCTAssertNil(result.activatedWorkspaceID)
        XCTAssertEqual(editor.projectWorkspaces, [])
        XCTAssertNil(editor.activeProjectID)
        XCTAssertNil(editor.projectURL)
        XCTAssertEqual(editor.fileTree, [])
        XCTAssertFalse(fileManager.fileExists(atPath: linkedURL.path(percentEncoded: false)))
    }

    func testToggleDirectoryChainsThroughSingleDirectoryChildren() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstURL = rootURL.appending(path: "First")
        let secondURL = firstURL.appending(path: "Second")
        let thirdURL = secondURL.appending(path: "Third")
        try fileManager.createDirectory(at: thirdURL, withIntermediateDirectories: true)
        try "leaf".write(to: thirdURL.appending(path: "Leaf.txt"), atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.toggleDirectory(firstURL)

        let firstNode = try XCTUnwrap(editor.fileTree.first)
        let secondNode = try XCTUnwrap(firstNode.children?.first)
        let thirdNode = try XCTUnwrap(secondNode.children?.first)

        XCTAssertEqual(firstNode.name, "First")
        XCTAssertTrue(firstNode.isExpanded)
        XCTAssertFalse(firstNode.isLoadingChildren)
        XCTAssertEqual(secondNode.name, "Second")
        XCTAssertTrue(secondNode.isExpanded)
        XCTAssertFalse(secondNode.isLoadingChildren)
        XCTAssertEqual(thirdNode.name, "Third")
        XCTAssertTrue(thirdNode.isExpanded)
        XCTAssertFalse(thirdNode.isLoadingChildren)
        XCTAssertEqual(thirdNode.children?.map(\.name), ["Leaf.txt"])
    }

    func testToggleDirectoryDoesNotChainWhenDirectoryContainsAFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstURL = rootURL.appending(path: "First")
        let secondURL = firstURL.appending(path: "Second")
        try fileManager.createDirectory(at: secondURL, withIntermediateDirectories: true)
        try "readme".write(to: firstURL.appending(path: "README.md"), atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.toggleDirectory(firstURL)

        let firstNode = try XCTUnwrap(editor.fileTree.first)
        let secondNode = try XCTUnwrap(firstNode.children?.first)

        XCTAssertTrue(firstNode.isExpanded)
        XCTAssertEqual(firstNode.children?.map(\.name), ["Second", "README.md"])
        XCTAssertEqual(secondNode.name, "Second")
        XCTAssertFalse(secondNode.isExpanded)
        XCTAssertNil(secondNode.children)
    }

    func testExpandSelectedDirectoryChainsThroughSingleDirectoryChildren() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstURL = rootURL.appending(path: "First")
        let secondURL = firstURL.appending(path: "Second")
        try fileManager.createDirectory(at: secondURL, withIntermediateDirectories: true)
        try "leaf".write(to: secondURL.appending(path: "Leaf.txt"), atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        editor.selectFileTreeNode(firstURL)
        await editor.expandSelectedFileTreeNode()

        let firstNode = try XCTUnwrap(editor.fileTree.first)
        let secondNode = try XCTUnwrap(firstNode.children?.first)

        let selectedURL = try XCTUnwrap(editor.selectedFileTreeURL)
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedURL, firstURL))
        XCTAssertTrue(firstNode.isExpanded)
        XCTAssertTrue(secondNode.isExpanded)
        XCTAssertEqual(secondNode.children?.map(\.name), ["Leaf.txt"])
    }

    func testFocusSelectedFileInTreeExpandsAncestorsAndSelectsFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Sources")
        let nestedURL = sourceURL.appending(path: "Nested")
        let fileURL = nestedURL.appending(path: "Feature.swift")
        try fileManager.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "feature".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        XCTAssertTrue(editor.canFocusSelectedFileInTree)
        let didFocus = await editor.focusSelectedFileInTree()
        XCTAssertTrue(didFocus)

        let sourceNode = try XCTUnwrap(editor.fileTree.first)
        let nestedNode = try XCTUnwrap(sourceNode.children?.first)
        let selectedURL = try XCTUnwrap(editor.selectedFileTreeURL)
        XCTAssertTrue(sourceNode.isExpanded)
        XCTAssertTrue(nestedNode.isExpanded)
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedURL, fileURL))
    }

    func testFocusSelectedFileInTreeSelectsRootFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "README.md")
        try "readme".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        XCTAssertTrue(editor.canFocusSelectedFileInTree)
        let didFocus = await editor.focusSelectedFileInTree()
        XCTAssertTrue(didFocus)

        let selectedURL = try XCTUnwrap(editor.selectedFileTreeURL)
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedURL, fileURL))
    }

    func testToggleFileTreeChangedFilesOnlyPublishesFilteredTree() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let sourceURL = rootURL.appending(path: "Sources")
        let changedURL = sourceURL.appending(path: "Changed.swift")
        let cleanURL = sourceURL.appending(path: "Clean.swift")
        let readmeURL = rootURL.appending(path: "README.md")
        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try "changed\n".write(to: changedURL, atomically: true, encoding: .utf8)
        try "clean\n".write(to: cleanURL, atomically: true, encoding: .utf8)
        try "readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        try "changed edited\n".write(to: changedURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)

        XCTAssertTrue(editor.canShowChangedFilesOnlyInFileTree)
        editor.toggleFileTreeChangedFilesOnly()

        XCTAssertTrue(editor.isFileTreeShowingChangedFilesOnly)
        XCTAssertEqual(editor.fileTree.map(\.name), ["Sources"])

        await editor.toggleDirectory(sourceURL)

        let sourceNode = try XCTUnwrap(editor.fileTree.first)
        XCTAssertEqual(sourceNode.children?.map(\.name), ["Changed.swift"])
    }

    func testOpeningDifferentProjectKeepsCurrentTabsAndUnsavedText() async throws {
        let firstRootURL = try makeTemporaryDirectory()
        let secondRootURL = try makeTemporaryDirectory()
        defer {
            try? fileManager.removeItem(at: firstRootURL)
            try? fileManager.removeItem(at: secondRootURL)
        }

        let firstFileURL = firstRootURL.appending(path: "First.txt")
        let secondFileURL = secondRootURL.appending(path: "Second.txt")
        try "first original".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second original".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()

        await editor.openProject(firstRootURL)
        await editor.openFile(firstFileURL)
        editor.updateSelectedText("first edited")
        let firstTabID = try XCTUnwrap(editor.selectedTabID)

        let result = await editor.openProject(secondRootURL)

        XCTAssertEqual(result, .requiresNewWindow(secondRootURL.standardizedFileURL))
        XCTAssertEqual(editor.selectedTabID, firstTabID)
        XCTAssertEqual(editor.selectedText, "first edited")
        XCTAssertTrue(editor.canSave)
        XCTAssertEqual(editor.projectWorkspaces.map(\.id), [firstRootURL.standardizedFileURL])
    }

    func testSavingAfterRejectedProjectOpenWritesCurrentProjectTab() async throws {
        let firstRootURL = try makeTemporaryDirectory()
        let secondRootURL = try makeTemporaryDirectory()
        defer {
            try? fileManager.removeItem(at: firstRootURL)
            try? fileManager.removeItem(at: secondRootURL)
        }

        let firstFileURL = firstRootURL.appending(path: "First.txt")
        let secondFileURL = secondRootURL.appending(path: "Second.txt")
        try "first original".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second original".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()

        await editor.openProject(firstRootURL)
        await editor.openFile(firstFileURL)
        editor.updateSelectedText("first edited")

        let result = await editor.openProject(secondRootURL)
        await editor.saveSelectedFile()

        XCTAssertEqual(result, .requiresNewWindow(secondRootURL.standardizedFileURL))
        XCTAssertEqual(try String(contentsOf: firstFileURL, encoding: .utf8), "first edited")
        XCTAssertEqual(try String(contentsOf: secondFileURL, encoding: .utf8), "second original")
    }

    func testOpenFileReplacesUneditedSelectedTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        let firstTabID = try XCTUnwrap(editor.selectedTabID)

        let closedDocument = await editor.openFile(secondFileURL)

        XCTAssertEqual(closedDocument?.documentID, firstFileURL)
        XCTAssertEqual(editor.tabs.count, 1)
        XCTAssertEqual(editor.tabs.first?.url, secondFileURL)
        XCTAssertNotEqual(editor.selectedTabID, firstTabID)
    }

    func testSearchFileOpenPreservesUneditedSelectedTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        let firstTabID = try XCTUnwrap(editor.selectedTabID)

        let closedDocument = await editor.openFilePreservingSelectedTab(secondFileURL)

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.tabs.count, 2)
        XCTAssertTrue(editor.tabs.contains { FileURLRewriter.urlsMatch($0.url, firstFileURL) })
        XCTAssertTrue(editor.tabs.contains { FileURLRewriter.urlsMatch($0.url, secondFileURL) })
        XCTAssertNotEqual(editor.selectedTabID, firstTabID)
        XCTAssertEqual(editor.selectedFileURL, secondFileURL)
    }

    func testTextSearchNavigationPreservesUneditedSelectedTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        let secondText = "before target after"
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try secondText.write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        let firstTabID = try XCTUnwrap(editor.selectedTabID)

        let targetRange = (secondText as NSString).range(of: "target")
        let closedDocument = await editor.navigateToFileRange(secondFileURL, range: targetRange)

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.tabs.count, 2)
        XCTAssertTrue(editor.tabs.contains { FileURLRewriter.urlsMatch($0.url, firstFileURL) })
        XCTAssertTrue(editor.tabs.contains { FileURLRewriter.urlsMatch($0.url, secondFileURL) })
        XCTAssertNotEqual(editor.selectedTabID, firstTabID)
        XCTAssertEqual(editor.selectedFileURL, secondFileURL)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let session = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, targetRange))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    func testOpenUnreadableUTF8FileDoesNotCreateTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let binaryFileURL = rootURL.appending(path: "Binary.bin")
        try Data([0xFF]).write(to: binaryFileURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        let closedDocument = await editor.openFile(binaryFileURL)

        XCTAssertNil(closedDocument)
        XCTAssertTrue(editor.tabs.isEmpty)
        XCTAssertNil(editor.selectedTabID)
        XCTAssertEqual(editor.errorMessage, ProjectFileError.unreadableUTF8File.localizedDescription)
    }

    func testOpenUnreadableUTF8FilePreservesExistingTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let textFileURL = rootURL.appending(path: "Note.txt")
        let binaryFileURL = rootURL.appending(path: "Binary.bin")
        try "note".write(to: textFileURL, atomically: true, encoding: .utf8)
        try Data([0xFF]).write(to: binaryFileURL)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(textFileURL)
        let selectedTabID = try XCTUnwrap(editor.selectedTabID)

        let closedDocument = await editor.openFile(binaryFileURL)

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.tabs.count, 1)
        XCTAssertEqual(editor.selectedTabID, selectedTabID)
        XCTAssertEqual(editor.selectedFileURL, textFileURL)
        XCTAssertEqual(editor.selectedText, "note")
        XCTAssertEqual(editor.errorMessage, ProjectFileError.unreadableUTF8File.localizedDescription)
    }

    func testCodeNavigationPreservesSourceTabAndMarksItUserEdited() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "".write(to: rootURL.appending(path: "settings.gradle.kts"), atomically: true, encoding: .utf8)
        let sourceDirectoryURL = rootURL.appending(path: "src/main/kotlin", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = sourceDirectoryURL.appending(path: "Source.kt")
        let targetURL = sourceDirectoryURL.appending(path: "Target.kt")
        let sourceText = "fun main() {\n    Target().run()\n}\n"
        let targetText = "class Target {}\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try targetText.write(to: targetURL, atomically: true, encoding: .utf8)

        let targetRange = (targetText as NSString).range(of: "Target")
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        try await waitForSymbolIndexReady(editor)
        await editor.openFile(sourceURL)
        let sourceTabID = try XCTUnwrap(editor.selectedTabID)
        let sourceOffset = (sourceText as NSString).range(
            of: "Target",
            options: [],
            range: NSRange(location: 10, length: (sourceText as NSString).length - 10)
        ).location
        editor.updateSelection(NSRange(location: sourceOffset, length: 0), in: sourceTabID)

        await editor.goToImplementation(at: sourceOffset, in: sourceTabID)

        XCTAssertEqual(editor.tabs.count, 2)
        let sourceTab = try XCTUnwrap(editor.tabs.first { FileURLRewriter.urlsMatch($0.url, sourceURL) })
        XCTAssertEqual(sourceTab.text, sourceText)
        XCTAssertTrue(sourceTab.hasUserEdited)
        XCTAssertFalse(sourceTab.hasUnsavedChanges)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, targetURL))

        let targetSession = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        XCTAssertTrue(NSEqualRanges(targetSession.selectedRange, targetRange))
        XCTAssertNotNil(targetSession.pendingSelectionRevealID)

        XCTAssertTrue(editor.canNavigateBack)
        await editor.navigateBackInHistory()

        let backTabID = try XCTUnwrap(editor.selectedTabID)
        let backTab = try XCTUnwrap(editor.tab(for: backTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(backTab.url, sourceURL))

        let backSession = try XCTUnwrap(editor.editorSession(for: backTabID))
        XCTAssertTrue(NSEqualRanges(backSession.selectedRange, NSRange(location: sourceOffset, length: 0)))
        XCTAssertTrue(editor.canNavigateForward)

        await editor.navigateForwardInHistory()

        let forwardTabID = try XCTUnwrap(editor.selectedTabID)
        let forwardTab = try XCTUnwrap(editor.tab(for: forwardTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(forwardTab.url, targetURL))

        let forwardSession = try XCTUnwrap(editor.editorSession(for: forwardTabID))
        XCTAssertTrue(NSEqualRanges(forwardSession.selectedRange, targetRange))
    }

    func testContextualCodeNavigationBuildsUsagesFromUnsavedOpenDocumentText() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "".write(to: rootURL.appending(path: "settings.gradle.kts"), atomically: true, encoding: .utf8)
        let sourceDirectoryURL = rootURL.appending(path: "src/main/kotlin", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = sourceDirectoryURL.appending(path: "Source.kt")
        let savedText = "class Target\nfun main() { Target() }\n"
        let unsavedText = "class Target\nfun main() { Target().edited() }\n"
        try savedText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let usageRange = (unsavedText as NSString).range(
            of: "Target",
            options: [],
            range: NSRange(location: 7, length: (unsavedText as NSString).length - 7)
        )
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        try await waitForSymbolIndexReady(editor)
        await editor.openFile(sourceURL)
        let sourceTabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateText(unsavedText, in: sourceTabID)

        let navigationResult = await editor.resolveImplementationOrReferences(at: 6, in: sourceTabID)
        let result = try XCTUnwrap(navigationResult)

        guard case .references(let usages, let title) = result else {
            return XCTFail("Expected usage references")
        }

        XCTAssertEqual(title, "Usages")
        XCTAssertEqual(usages.count, 1)
        XCTAssertEqual(usages[0].lineText, "fun main() { Target().edited() }")
        XCTAssertEqual(usages[0].lineNumber, 2)
        XCTAssertEqual(usages[0].column, 14)
        XCTAssertTrue(NSEqualRanges(usages[0].matchRange.nsRange, usageRange))
    }

    func testCodeUsageJumpPreservesSourceTabAndRecordsHistory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Definition.kt")
        let usageURL = rootURL.appending(path: "Usage.kt")
        let sourceText = "class Target\n"
        let usageText = "fun main() { Target() }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try usageText.write(to: usageURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(sourceURL)
        let sourceTabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateSelection(NSRange(location: 6, length: 0), in: sourceTabID)

        let usageRange = TextRange(location: 13, length: 6)
        let usage = CodeUsageResult.result(
            url: usageURL,
            range: usageRange,
            text: usageText,
            projectURL: rootURL
        )

        let closedDocument = await editor.navigateToCodeUsage(usage)

        XCTAssertNil(closedDocument)
        XCTAssertEqual(editor.tabs.count, 2)

        let sourceTab = try XCTUnwrap(editor.tabs.first { FileURLRewriter.urlsMatch($0.url, sourceURL) })
        XCTAssertTrue(sourceTab.hasUserEdited)
        XCTAssertFalse(sourceTab.hasUnsavedChanges)

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, usageURL))

        let usageSession = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        XCTAssertTrue(NSEqualRanges(usageSession.selectedRange, usageRange.nsRange))
        XCTAssertNotNil(usageSession.pendingSelectionRevealID)
        XCTAssertTrue(editor.canNavigateBack)

        await editor.navigateBackInHistory()

        let backTabID = try XCTUnwrap(editor.selectedTabID)
        let backTab = try XCTUnwrap(editor.tab(for: backTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(backTab.url, sourceURL))

        let backSession = try XCTUnwrap(editor.editorSession(for: backTabID))
        XCTAssertTrue(NSEqualRanges(backSession.selectedRange, NSRange(location: 6, length: 0)))
    }

    func testNavigateToFileRangeRecordsPreviousRangeInSameFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "first\nsecond\nthird".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)
        let originRange = NSRange(location: 0, length: 5)
        let targetRange = NSRange(location: 6, length: 6)
        editor.updateSelection(originRange, in: tabID)

        await editor.navigateToFileRange(fileURL, range: targetRange)

        let targetSession = try XCTUnwrap(editor.editorSession(for: tabID))
        XCTAssertTrue(NSEqualRanges(targetSession.selectedRange, targetRange))
        XCTAssertTrue(editor.canNavigateBack)

        await editor.navigateBackInHistory()

        let backSession = try XCTUnwrap(editor.editorSession(for: tabID))
        XCTAssertTrue(NSEqualRanges(backSession.selectedRange, originRange))
        XCTAssertTrue(editor.canNavigateForward)

        await editor.navigateForwardInHistory()

        let forwardSession = try XCTUnwrap(editor.editorSession(for: tabID))
        XCTAssertTrue(NSEqualRanges(forwardSession.selectedRange, targetRange))
    }

    func testOpeningDifferentProjectDoesNotClearNavigationHistory() async throws {
        let firstRootURL = try makeTemporaryDirectory()
        let secondRootURL = try makeTemporaryDirectory()
        defer {
            try? fileManager.removeItem(at: firstRootURL)
            try? fileManager.removeItem(at: secondRootURL)
        }

        let firstFileURL = firstRootURL.appending(path: "First.txt")
        let nextFileURL = firstRootURL.appending(path: "Next.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "next".write(to: nextFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(firstRootURL)
        await editor.openFile(firstFileURL)
        await editor.openFile(nextFileURL)
        XCTAssertTrue(editor.canNavigateBack)

        let result = await editor.openProject(secondRootURL)

        XCTAssertEqual(result, .requiresNewWindow(secondRootURL.standardizedFileURL))
        XCTAssertTrue(editor.canNavigateBack)

        await editor.navigateBackInHistory()

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, firstFileURL))
    }

    func testManualNavigationAfterBackClearsForwardHistory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        let thirdFileURL = rootURL.appending(path: "Third.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        await editor.openFile(secondFileURL)
        await editor.navigateBackInHistory()

        XCTAssertTrue(editor.canNavigateForward)

        await editor.openFile(thirdFileURL)

        XCTAssertFalse(editor.canNavigateForward)
        XCTAssertTrue(editor.canNavigateBack)
    }

    func testBackNavigationReopensClosedFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        let firstTabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateSelectedText("first edited")
        await editor.openFile(secondFileURL)

        XCTAssertNotNil(editor.closeTab(firstTabID))

        await editor.navigateBackInHistory()

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, firstFileURL))
    }

    func testBackNavigationSkipsDeletedClosedFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        let thirdFileURL = rootURL.appending(path: "Third.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        editor.updateSelectedText("first edited")
        await editor.openFile(secondFileURL)
        let secondTabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateSelectedText("second edited")
        await editor.openFile(thirdFileURL)

        XCTAssertNotNil(editor.closeTab(secondTabID))
        try fileManager.removeItem(at: secondFileURL)

        await editor.navigateBackInHistory()

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, firstFileURL))
    }

    func testRenameRewritesNavigationHistoryURLs() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        let renamedFileURL = rootURL.appending(path: "Renamed.txt").standardizedFileURL
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        await editor.openFile(secondFileURL)
        await editor.renameFileTreeNode(firstFileURL, to: "Renamed.txt")
        await editor.navigateBackInHistory()

        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, renamedFileURL))
    }

    func testRejectedDifferentProjectOpenPreservesEditorSessionState() async throws {
        let firstRootURL = try makeTemporaryDirectory()
        let secondRootURL = try makeTemporaryDirectory()
        defer {
            try? fileManager.removeItem(at: firstRootURL)
            try? fileManager.removeItem(at: secondRootURL)
        }

        let firstFileURL = firstRootURL.appending(path: "First.txt")
        try "first original".write(to: firstFileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()

        await editor.openProject(firstRootURL)
        await editor.openFile(firstFileURL)
        let firstTabID = try XCTUnwrap(editor.selectedTabID)
        let firstSession = try XCTUnwrap(editor.editorSession(for: firstTabID))

        editor.updateSelection(NSRange(location: 3, length: 4), in: firstTabID)
        editor.updateScrollOrigin(CGPoint(x: 0, y: 80), in: firstTabID)

        let result = await editor.openProject(secondRootURL)

        XCTAssertEqual(result, .requiresNewWindow(secondRootURL.standardizedFileURL))
        let restoredSession = try XCTUnwrap(editor.editorSession(for: firstTabID))
        XCTAssertTrue(firstSession === restoredSession)
        XCTAssertTrue(NSEqualRanges(restoredSession.selectedRange, NSRange(location: 3, length: 4)))
        XCTAssertEqual(restoredSession.scrollOrigin, CGPoint(x: 0, y: 80))
    }

    func testRevealRangeRequestsEditorSessionSelectionReveal() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "first\nsecond\nthird".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)

        editor.revealRange(NSRange(location: 6, length: 6), in: tabID)

        let session = try XCTUnwrap(editor.editorSession(for: tabID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, NSRange(location: 6, length: 6)))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func initializeRepository(at rootURL: URL) throws {
        try runGit(["init", "-b", "main"], in: rootURL)
        try runGit(["config", "user.email", "test@example.com"], in: rootURL)
        try runGit(["config", "user.name", "Test"], in: rootURL)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in rootURL: URL) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = try gitExecutableURL()
        process.arguments = arguments
        process.currentDirectoryURL = rootURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8) ?? "git failed"
            XCTFail(message)
            return ""
        }

        return String(data: output, encoding: .utf8) ?? ""
    }

    private func gitExecutableURL() throws -> URL {
        let url = URL(filePath: "/usr/bin/git")
        guard fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) else {
            throw XCTSkip("git executable is not available")
        }

        return url
    }

    private func waitForSymbolIndexReady(
        _ editor: EditorState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<50 {
            if case .ready = editor.symbolIndexStatus {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for symbol index readiness.", file: file, line: line)
    }

    private func waitForReviewDiffLoaded(
        _ editor: EditorState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> GitReviewDiffSnapshot {
        for _ in 0..<50 {
            if case .loaded(let snapshot) = editor.reviewDiffState {
                return snapshot
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for review diff.", file: file, line: line)
        throw GitReviewDiffError.gitCommandFailed("Timed out waiting for review diff.")
    }

    private func waitForReviewDiffCallCount(
        _ expectedCount: Int,
        in gitService: EditorStateWorkspaceMockGitService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [EditorStateWorkspaceMockGitService.ReviewDiffCall] {
        for _ in 0..<50 {
            let calls = gitService.reviewDiffCalls()
            if calls.count >= expectedCount {
                return calls
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for review diff calls.", file: file, line: line)
        throw GitReviewDiffError.gitCommandFailed("Timed out waiting for review diff calls.")
    }

    private func waitForReviewBase(
        _ editor: EditorState,
        _ expectedBase: GitReviewDiffBase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<50 {
            if editor.reviewDiffBase == expectedBase {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for review base.", file: file, line: line)
    }

    private func waitForStoredReviewBase(
        _ expectedBase: GitReviewDiffBase,
        branchName: String,
        metadataDirectoryURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let store = WorktreeMetadataStore()
        for _ in 0..<50 {
            if await store.reviewBase(forBranch: branchName, metadataDirectoryURL: metadataDirectoryURL) == expectedBase {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for stored review base.", file: file, line: line)
    }

    private func waitForGitHubPullRequestStatus(
        _ editor: EditorState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> GitHubPullRequestStatus {
        for _ in 0..<50 {
            if let status = editor.githubPullRequestStatus {
                return status
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for GitHub pull request.", file: file, line: line)
        throw GitReviewDiffError.gitCommandFailed("Timed out waiting for GitHub pull request.")
    }

    private func waitForGitHubPullRequestStatus(
        _ editor: EditorState,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        expectedStatus: GitHubPullRequestStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let workspaceID = workspaceID.standardizedFileURL
        for _ in 0..<50 {
            if editor.githubPullRequestStatusesByProjectID[workspaceID] == expectedStatus {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for workspace GitHub pull request.", file: file, line: line)
    }

    private func waitForGitHubPullRequestLoadingState(
        _ editor: EditorState,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        isLoading: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let workspaceID = workspaceID.standardizedFileURL
        for _ in 0..<50 {
            if editor.githubPullRequestLoadingProjectIDs.contains(workspaceID) == isLoading {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for workspace GitHub pull request loading state.", file: file, line: line)
    }

    private func waitForGitHubPullRequestCall(
        _ service: EditorStateWorkspaceMockGitHubPullRequestService,
        branchName: String,
        baseBranchName: String?,
        openedRootURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> EditorStateWorkspaceMockGitHubPullRequestService.Call {
        let expectedCall = EditorStateWorkspaceMockGitHubPullRequestService.Call(
            branchName: branchName,
            baseBranchName: baseBranchName,
            openedRootURL: openedRootURL.standardizedFileURL
        )
        for _ in 0..<50 {
            if let call = await service.calls().first(where: { $0 == expectedCall }) {
                return call
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for GitHub pull request lookup.", file: file, line: line)
        throw GitReviewDiffError.gitCommandFailed("Timed out waiting for GitHub pull request lookup.")
    }

    private func makeGitSnapshot(
        rootURL: URL,
        branch: GitBranchState,
        worktreeKind: GitWorktreeKind = .main,
        worktreeRootURLs: [URL]? = nil,
        worktrees: [GitWorktreeInfo]? = nil,
        isRuriStyleWorktree: Bool = false,
        gitDirectoryURL: URL? = nil,
        gitCommonDirectoryURL: URL? = nil
    ) -> GitRepositorySnapshot {
        let rootURL = rootURL.standardizedFileURL
        let gitDirectoryURL = gitDirectoryURL?.standardizedFileURL
            ?? rootURL.appending(path: ".git", directoryHint: .notDirectory)
        let gitCommonDirectoryURL = gitCommonDirectoryURL?.standardizedFileURL ?? gitDirectoryURL
        let worktreeRootURLs = worktreeRootURLs ?? [rootURL]
        let worktrees = worktrees ?? [
            GitWorktreeInfo(rootURL: rootURL, branch: branch, headRevision: nil, kind: worktreeKind)
        ]

        return GitRepositorySnapshot(
            repositoryRootURL: rootURL,
            worktreeRootURL: rootURL,
            openedRootURL: rootURL,
            gitDirectoryURL: gitDirectoryURL,
            gitCommonDirectoryURL: gitCommonDirectoryURL,
            worktreeKind: worktreeKind,
            worktreeRootURLs: worktreeRootURLs,
            worktrees: worktrees,
            isRuriStyleWorktree: isRuriStyleWorktree,
            branch: branch,
            changesByURL: [:],
            diffsByURL: [:]
        )
    }
}

private actor EditorStateWorkspaceMockGitHubPullRequestService: GitHubPullRequestServiceProtocol {
    struct Call: Equatable {
        let branchName: String
        let baseBranchName: String?
        let openedRootURL: URL
    }

    private let pullRequests: [URL: [String: GitHubPullRequestStatus]]
    private let pullRequestDetailsByRootAndNumber: [URL: [Int: GitHubPullRequestDetails]]
    private let responseDelayNanoseconds: UInt64
    private var storedCalls: [Call] = []

    init(
        pullRequests: [URL: [String: GitHubPullRequestStatus]],
        pullRequestDetailsByRootAndNumber: [URL: [Int: GitHubPullRequestDetails]] = [:],
        responseDelayNanoseconds: UInt64 = 0
    ) {
        self.pullRequests = pullRequests.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
        self.pullRequestDetailsByRootAndNumber = pullRequestDetailsByRootAndNumber.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
        self.responseDelayNanoseconds = responseDelayNanoseconds
    }

    func pullRequestStatus(
        forBranch branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async -> GitHubPullRequestStatus? {
        let openedRootURL = openedRootURL.standardizedFileURL
        storedCalls.append(Call(
            branchName: branchName,
            baseBranchName: baseBranch,
            openedRootURL: openedRootURL
        ))
        if responseDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }
        return pullRequests[openedRootURL]?[branchName]
    }

    func pullRequestDetails(
        number: Int,
        openedRootURL: URL
    ) async throws -> GitHubPullRequestDetails {
        let openedRootURL = openedRootURL.standardizedFileURL
        guard let details = pullRequestDetailsByRootAndNumber[openedRootURL]?[number] else {
            throw GitHubPullRequestServiceError.invalidResponse
        }

        return details
    }

    func calls() -> [Call] {
        storedCalls
    }
}

nonisolated private final class EditorStateWorkspaceMockGitService: GitServiceProtocol, @unchecked Sendable {
    struct ReviewDiffCall: Equatable {
        let base: GitReviewDiffBase
        let options: GitReviewDiffOptions
        let openedRootURL: URL
    }

    struct ReviewDiffUpdateCall: Equatable {
        let base: GitReviewDiffBase
        let options: GitReviewDiffOptions
        let fileURLs: [URL]
        let openedRootURL: URL
    }

    let snapshots: [URL: GitRepositorySnapshot]
    let fileSnapshots: [URL: GitFileSnapshot]
    let reviewDiffs: [URL: GitReviewDiffSnapshot]
    let reviewDiffUpdates: [URL: GitReviewDiffUpdate]
    let expectedReviewBases: [URL: GitReviewDiffBase]
    let fileContentsByRootAndRevision: [URL: [String: [String: String]]]
    let githubRepositoryIdentitiesByRoot: [URL: [GitHubRepositoryIdentity]]
    private let lock = NSLock()
    private var storedReviewDiffCalls: [ReviewDiffCall] = []
    private var storedReviewDiffUpdateCalls: [ReviewDiffUpdateCall] = []

    init(
        snapshots: [URL: GitRepositorySnapshot],
        fileSnapshots: [URL: GitFileSnapshot] = [:],
        reviewDiffs: [URL: GitReviewDiffSnapshot] = [:],
        reviewDiffUpdates: [URL: GitReviewDiffUpdate] = [:],
        expectedReviewBaseBranches: [URL: String] = [:],
        expectedReviewBases: [URL: GitReviewDiffBase] = [:],
        fileContentsByRootAndRevision: [URL: [String: [String: String]]] = [:],
        githubRepositoryIdentitiesByRoot: [URL: [GitHubRepositoryIdentity]] = [:]
    ) {
        self.snapshots = snapshots
        self.fileSnapshots = fileSnapshots.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
        self.reviewDiffs = reviewDiffs
        self.reviewDiffUpdates = reviewDiffUpdates.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
        self.expectedReviewBases = expectedReviewBases.merging(
            expectedReviewBaseBranches.mapValues { GitReviewDiffBase.branch($0) }
        ) { explicit, _ in explicit }
        self.fileContentsByRootAndRevision = fileContentsByRootAndRevision
        self.githubRepositoryIdentitiesByRoot = githubRepositoryIdentitiesByRoot.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
    }

    func repositoryStatus(for openedRootURL: URL) async -> GitRepositoryStatus {
        guard let snapshot = snapshots[openedRootURL.standardizedFileURL] else {
            return .notRepository(openedRootURL.standardizedFileURL)
        }

        return .repository(snapshot)
    }

    func fileSnapshot(for fileURL: URL, openedRootURL: URL) async -> GitFileSnapshot? {
        fileSnapshots[fileURL.standardizedFileURL]
    }

    func createWorktree(
        branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo {
        throw GitWorktreeCreationError.notRepository(openedRootURL.standardizedFileURL)
    }

    func deleteWorktree(openedRootURL: URL) async throws {
        throw GitWorktreeDeletionError.notRepository(openedRootURL.standardizedFileURL)
    }

    func switchBranch(named branchName: String, openedRootURL: URL) async throws {
        throw GitBranchSwitchError.notRepository(openedRootURL.standardizedFileURL)
    }

    func githubRepositoryIdentities(openedRootURL: URL) async -> [GitHubRepositoryIdentity] {
        githubRepositoryIdentitiesByRoot[openedRootURL.standardizedFileURL] ?? []
    }

    func reviewDiff(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot {
        let openedRootURL = openedRootURL.standardizedFileURL
        lock.lock()
        storedReviewDiffCalls.append(ReviewDiffCall(
            base: base,
            options: options,
            openedRootURL: openedRootURL
        ))
        lock.unlock()

        if let expectedBase = expectedReviewBases[openedRootURL],
           expectedBase != base {
            throw GitReviewDiffError.invalidBaseBranch(base.displayName)
        }

        guard let snapshot = reviewDiffs[openedRootURL] else {
            throw GitReviewDiffError.notRepository(openedRootURL)
        }

        return snapshot
    }

    func reviewDiffUpdate(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        fileURLs: [URL],
        openedRootURL: URL
    ) async throws -> GitReviewDiffUpdate {
        let openedRootURL = openedRootURL.standardizedFileURL
        let normalizedFileURLs = fileURLs.map(\.standardizedFileURL)
        lock.lock()
        storedReviewDiffUpdateCalls.append(ReviewDiffUpdateCall(
            base: base,
            options: options,
            fileURLs: normalizedFileURLs,
            openedRootURL: openedRootURL
        ))
        lock.unlock()

        if let expectedBase = expectedReviewBases[openedRootURL],
           expectedBase != base {
            throw GitReviewDiffError.invalidBaseBranch(base.displayName)
        }

        guard let update = reviewDiffUpdates[openedRootURL] else {
            throw GitReviewDiffError.notRepository(openedRootURL)
        }

        return update
    }

    func reviewDiffCalls() -> [ReviewDiffCall] {
        lock.lock()
        defer { lock.unlock() }
        return storedReviewDiffCalls
    }

    func reviewDiffUpdateCalls() -> [ReviewDiffUpdateCall] {
        lock.lock()
        defer { lock.unlock() }
        return storedReviewDiffUpdateCalls
    }

    func fileContents(
        at revision: String,
        relativePath: String,
        openedRootURL: URL
    ) async throws -> String {
        let openedRootURL = openedRootURL.standardizedFileURL
        guard let text = fileContentsByRootAndRevision[openedRootURL]?[revision]?[relativePath] else {
            throw GitReviewDiffError.gitCommandFailed("Missing test file contents.")
        }

        return text
    }
}

nonisolated private final class RecordingWorktreeInitializationService: WorktreeInitializationServiceProtocol, @unchecked Sendable {
    struct Call: Equatable {
        let command: String
        let worktreeRootURL: URL
    }

    private let lock = NSLock()
    private let error: Error?
    private var storedCalls: [Call] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func run(command: String, in worktreeRootURL: URL) async throws {
        let worktreeRootURL = worktreeRootURL.standardizedFileURL
        lock.lock()
        storedCalls.append(Call(command: command, worktreeRootURL: worktreeRootURL))
        lock.unlock()

        if let error {
            throw error
        }

        try "\(command)\n".write(
            to: worktreeRootURL.appending(path: "initialized.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    func calls() -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return storedCalls
    }
}

nonisolated private final class RecordingEditorStateWorkspaceGitService: GitServiceProtocol, @unchecked Sendable {
    private let snapshots: [URL: GitRepositorySnapshot]
    private let lock = NSLock()
    private var requestedRepositoryStatusURLs: [URL] = []

    init(snapshots: [URL: GitRepositorySnapshot]) {
        self.snapshots = snapshots
    }

    func repositoryStatus(for openedRootURL: URL) async -> GitRepositoryStatus {
        let openedRootURL = openedRootURL.standardizedFileURL
        lock.lock()
        requestedRepositoryStatusURLs.append(openedRootURL)
        lock.unlock()

        guard let snapshot = snapshots[openedRootURL] else {
            return .notRepository(openedRootURL)
        }

        return .repository(snapshot)
    }

    func repositoryStatusURLs() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestedRepositoryStatusURLs
    }

    func resetRepositoryStatusURLs() {
        lock.lock()
        requestedRepositoryStatusURLs = []
        lock.unlock()
    }

    func fileSnapshot(for fileURL: URL, openedRootURL: URL) async -> GitFileSnapshot? {
        nil
    }

    func createWorktree(
        branchName: String,
        baseBranch: String?,
        openedRootURL: URL
    ) async throws -> GitWorktreeInfo {
        throw GitWorktreeCreationError.notRepository(openedRootURL.standardizedFileURL)
    }

    func deleteWorktree(openedRootURL: URL) async throws {
        throw GitWorktreeDeletionError.notRepository(openedRootURL.standardizedFileURL)
    }

    func switchBranch(named branchName: String, openedRootURL: URL) async throws {
        throw GitBranchSwitchError.notRepository(openedRootURL.standardizedFileURL)
    }

    func githubRepositoryIdentities(openedRootURL: URL) async -> [GitHubRepositoryIdentity] {
        []
    }

    func reviewDiff(
        base: GitReviewDiffBase,
        options: GitReviewDiffOptions,
        openedRootURL: URL
    ) async throws -> GitReviewDiffSnapshot {
        throw GitReviewDiffError.notRepository(openedRootURL.standardizedFileURL)
    }

    func fileContents(
        at revision: String,
        relativePath: String,
        openedRootURL: URL
    ) async throws -> String {
        throw GitReviewDiffError.notRepository(openedRootURL.standardizedFileURL)
    }
}
