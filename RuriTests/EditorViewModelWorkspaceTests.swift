//
//  EditorViewModelWorkspaceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorViewModelWorkspaceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testOpenProjectRequiresNewWindowForDifferentFolder() async throws {
        let firstRootURL = try makeTemporaryDirectory()
        let secondRootURL = try makeTemporaryDirectory()
        defer {
            try? fileManager.removeItem(at: firstRootURL)
            try? fileManager.removeItem(at: secondRootURL)
        }

        let editor = EditorViewModel()

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

        let editor = EditorViewModel()

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
        let editor = EditorViewModel(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)

        XCTAssertEqual(editor.projectName, "RegularProject")
    }

    func testProjectNameUsesParentDirectoryForRuriBaseProject() async throws {
        let parentURL = try makeTemporaryDirectory()
        let projectParentURL = parentURL.appending(path: "RuriProject", directoryHint: .isDirectory)
        let rootURL = projectParentURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let editor = EditorViewModel(isFileWatchingEnabled: false)

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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let gitService = EditorViewModelWorkspaceMockGitService(
            snapshots: [
                rootURL.standardizedFileURL: repositorySnapshot
            ],
            reviewDiffs: [
                rootURL.standardizedFileURL: reviewSnapshot
            ]
        )
        let editor = EditorViewModel(
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
        let gitService = EditorViewModelWorkspaceMockGitService(
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
        let editor = EditorViewModel(
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
            EditorViewModelWorkspaceMockGitService.ReviewDiffUpdateCall(
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let gitService = EditorViewModelWorkspaceMockGitService(
            snapshots: [
                rootURL.standardizedFileURL: repositorySnapshot
            ]
        )
        let firstEditor = EditorViewModel(
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

        let secondEditor = EditorViewModel(
            gitService: gitService,
            isFileWatchingEnabled: false
        )

        await secondEditor.openProject(rootURL)
        try await waitForReviewBase(secondEditor, .branch("origin/main"))
    }

    func testReviewDiffViewedStateLoadsFromLocalStoreAndInvalidatesChangedFingerprints() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let metadataDirectoryURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()
        try await store.saveViewedReviewFile(
            path: "Matched.txt",
            fingerprint: "fp-match",
            forBranch: currentBranch,
            metadataDirectoryURL: metadataDirectoryURL,
            repositoryRootURL: nil
        )
        try await store.saveViewedReviewFile(
            path: "Stale.txt",
            fingerprint: "fp-old",
            forBranch: currentBranch,
            metadataDirectoryURL: metadataDirectoryURL,
            repositoryRootURL: nil
        )

        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [
                makeReviewFileDiff(path: "Matched.txt", contentFingerprint: "fp-match"),
                makeReviewFileDiff(path: "Stale.txt", contentFingerprint: "fp-new")
            ]
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch(currentBranch))
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [:]),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        try await TestSupport.waitUntil("viewed file paths") {
            editor.reviewDiffViewedFilePaths == ["Matched.txt"]
        }
        XCTAssertFalse(editor.reviewDiffViewedSyncsToPullRequest)
    }

    func testChangedLocalViewedEntryIsDismissedPersistently() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let metadataDirectoryURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()
        try await store.saveViewedReviewFile(
            path: "Stale.txt",
            fingerprint: "fp-old",
            forBranch: currentBranch,
            metadataDirectoryURL: metadataDirectoryURL,
            repositoryRootURL: nil
        )

        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [
                makeReviewFileDiff(path: "Stale.txt", contentFingerprint: "fp-new")
            ]
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch(currentBranch))
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [:]),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        // 不一致を観測した時点でストアのエントリが削除され、内容が fp-old に戻っても復活しない。
        try await TestSupport.waitUntil("dismissed viewed entry") {
            await store.viewedReviewFiles(
                forBranch: currentBranch,
                metadataDirectoryURL: metadataDirectoryURL
            ) == [:]
        }
        XCTAssertEqual(editor.reviewDiffViewedFilePaths, [])
    }

    func testSetReviewDiffFileViewedPersistsFingerprintToLocalStore() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/local"
        let metadataDirectoryURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .uncommitted,
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [
                makeReviewFileDiff(path: "Changed.txt", contentFingerprint: "fp-changed")
            ]
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch(currentBranch))
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [:]),
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        editor.setReviewDiffFileViewed(true, path: "Changed.txt")

        XCTAssertEqual(editor.reviewDiffViewedFilePaths, ["Changed.txt"])
        let store = WorktreeMetadataStore()
        try await TestSupport.waitUntil("stored viewed entry") {
            await store.viewedReviewFiles(
                forBranch: currentBranch,
                metadataDirectoryURL: metadataDirectoryURL
            ) == ["Changed.txt": "fp-changed"]
        }

        editor.setReviewDiffFileViewed(false, path: "Changed.txt")

        XCTAssertEqual(editor.reviewDiffViewedFilePaths, [])
        try await TestSupport.waitUntil("removed viewed entry") {
            await store.viewedReviewFiles(
                forBranch: currentBranch,
                metadataDirectoryURL: metadataDirectoryURL
            ) == [:]
        }
    }

    func testReviewDiffViewedStateUsesPullRequestAsSourceOfTruthAndSyncsToggles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/pr"
        let pullRequestStatus = GitHubPullRequestStatus.pullRequest(GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open
        ))
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .branch("main"),
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [
                makeReviewFileDiff(path: "PRFile.txt", contentFingerprint: "fp-pr"),
                makeReviewFileDiff(path: "LocalOnly.txt", contentFingerprint: "fp-local")
            ]
        )
        let fileViewsService = EditorViewModelWorkspaceMockGitHubPullRequestFileViewsService(
            result: .available(GitHubPullRequestFileViews(
                pullRequestNodeID: "PR_node",
                statesByPath: [
                    "PRFile.txt": .viewed,
                    "OutsideDiff.txt": .unviewed
                ]
            ))
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch(currentBranch))
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
                rootURL: [currentBranch: pullRequestStatus]
            ]),
            githubPullRequestFileViewsService: fileViewsService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        try await TestSupport.waitUntil("PR viewed state") {
            editor.reviewDiffViewedSyncsToPullRequest
                && editor.reviewDiffViewedFilePaths == ["PRFile.txt"]
        }

        editor.setReviewDiffFileViewed(false, path: "PRFile.txt")
        XCTAssertEqual(editor.reviewDiffViewedFilePaths, [])
        try await TestSupport.waitUntil("unmark mutation call") {
            let calls = await fileViewsService.setCalls()
            return calls.count == 1
                && calls[0].viewed == false
                && calls[0].pullRequestNodeID == "PR_node"
                && calls[0].path == "PRFile.txt"
                && FileURLRewriter.urlsMatch(calls[0].openedRootURL, rootURL)
        }

        // PRのファイル一覧に含まれないパスはローカル管理へフォールバックする。
        editor.setReviewDiffFileViewed(true, path: "LocalOnly.txt")
        let store = WorktreeMetadataStore()
        try await TestSupport.waitUntil("local fallback entry") {
            await store.viewedReviewFiles(
                forBranch: currentBranch,
                metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
            ) == ["LocalOnly.txt": "fp-local"]
        }
        let setCalls = await fileViewsService.setCalls()
        XCTAssertEqual(setCalls.count, 1)
    }

    func testToggleBeforePullRequestFileViewsLoadDefersRoutingToPullRequest() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/pr"
        let pullRequestStatus = GitHubPullRequestStatus.pullRequest(GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open
        ))
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .branch("main"),
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [
                makeReviewFileDiff(path: "PRFile.txt", contentFingerprint: "fp-pr")
            ]
        )
        let fileViewsService = EditorViewModelWorkspaceMockGitHubPullRequestFileViewsService(
            result: .available(GitHubPullRequestFileViews(
                pullRequestNodeID: "PR_node",
                statesByPath: ["PRFile.txt": .unviewed]
            )),
            fileViewsDelayNanoseconds: 1_000_000_000
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch(currentBranch))
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
                rootURL: [currentBranch: pullRequestStatus]
            ]),
            githubPullRequestFileViewsService: fileViewsService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        _ = try await waitForGitHubPullRequestStatus(editor)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        // fileViews のロード(1秒遅延)が完了する前にトグルする。
        editor.setReviewDiffFileViewed(true, path: "PRFile.txt")
        XCTAssertEqual(editor.reviewDiffViewedFilePaths, ["PRFile.txt"])

        // ロード適用後、保留トグルが PR mutation として送られ、チェック状態が維持される。
        try await TestSupport.waitUntil("deferred mutation call") {
            let calls = await fileViewsService.setCalls()
            return calls.contains { $0.viewed && $0.pullRequestNodeID == "PR_node" && $0.path == "PRFile.txt" }
        }
        XCTAssertTrue(editor.reviewDiffViewedFilePaths.contains("PRFile.txt"))

        // ローカルストアには書かれていない(誤ルーティングしていない)。
        let localEntries = await WorktreeMetadataStore().viewedReviewFiles(
            forBranch: currentBranch,
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        )
        XCTAssertEqual(localEntries, [:])
    }

    func testSetReviewDiffFileViewedRollsBackOnPullRequestMutationFailure() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let currentBranch = "feature/pr"
        let pullRequestStatus = GitHubPullRequestStatus.pullRequest(GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open
        ))
        let reviewSnapshot = GitReviewDiffSnapshot(
            base: .branch("main"),
            targetBranch: .branch(currentBranch),
            targetWorktreeRootURL: rootURL,
            baseRevision: "abc123",
            files: [
                makeReviewFileDiff(path: "PRFile.txt", contentFingerprint: "fp-pr")
            ]
        )
        let fileViewsService = EditorViewModelWorkspaceMockGitHubPullRequestFileViewsService(
            result: .available(GitHubPullRequestFileViews(
                pullRequestNodeID: "PR_node",
                statesByPath: ["PRFile.txt": .unviewed]
            )),
            setError: GitHubPullRequestFileViewsError.commandFailed("mutation failed")
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch(currentBranch))
                ],
                reviewDiffs: [
                    rootURL.standardizedFileURL: reviewSnapshot
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
                rootURL: [currentBranch: pullRequestStatus]
            ]),
            githubPullRequestFileViewsService: fileViewsService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)
        try await TestSupport.waitUntil("PR viewed state") {
            editor.reviewDiffViewedSyncsToPullRequest
        }

        editor.setReviewDiffFileViewed(true, path: "PRFile.txt")
        XCTAssertEqual(editor.reviewDiffViewedFilePaths, ["PRFile.txt"])

        try await TestSupport.waitUntil("optimistic rollback") {
            editor.reviewDiffViewedFilePaths.isEmpty && editor.currentError != nil
        }
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
            rootURL.standardizedFileURL: [
                "feature/status-pr": .pullRequest(pullRequest)
            ]
        ])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
            EditorViewModelWorkspaceMockGitHubPullRequestService.Call(
                branchName: "feature/status-pr",
                baseBranchName: nil,
                openedRootURL: rootURL.standardizedFileURL
            )
        ])
    }

    func testGitHubPullRequestPollingRefreshesPeriodicallyWhileApplicationIsActive() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let pullRequest = GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open,
            mergeableState: .mergeable
        )
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
            rootURL.standardizedFileURL: [
                "feature/status-pr": .pullRequest(pullRequest)
            ]
        ])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch("feature/status-pr")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false,
            githubPullRequestPollingIntervalNanoseconds: 20_000_000,
            isApplicationActive: { true }
        )

        await editor.openProject(rootURL)

        try await TestSupport.waitUntil("GitHub pull request polling calls") {
            await gitHubPullRequestService.calls().count >= 3
        }
        XCTAssertEqual(editor.githubPullRequestStatus, .pullRequest(pullRequest))
    }

    func testGitHubPullRequestPollingDoesNotRunWhileApplicationIsInactive() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
            rootURL.standardizedFileURL: [
                "feature/status-pr": .pullRequest(GitHubPullRequestInfo(
                    number: 42,
                    url: URL(string: "https://github.com/owner/repo/pull/42")!,
                    lifecycleState: .open
                ))
            ]
        ])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch("feature/status-pr")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false,
            githubPullRequestPollingIntervalNanoseconds: 20_000_000,
            isApplicationActive: { false }
        )

        await editor.openProject(rootURL)
        _ = try await waitForGitHubPullRequestStatus(editor)

        try await Task.sleep(nanoseconds: 150_000_000)
        let calls = await gitHubPullRequestService.calls()
        XCTAssertEqual(calls.count, 1, "初回の lookupKey 変更による取得以外は走らないこと")
    }

    func testGitHubPullRequestRefreshesImmediatelyOnApplicationActivation() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
            rootURL.standardizedFileURL: [
                "feature/status-pr": .pullRequest(GitHubPullRequestInfo(
                    number: 42,
                    url: URL(string: "https://github.com/owner/repo/pull/42")!,
                    lifecycleState: .open
                ))
            ]
        ])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch("feature/status-pr")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false,
            githubPullRequestPollingIntervalNanoseconds: 0,
            isApplicationActive: { true }
        )

        await editor.openProject(rootURL)
        _ = try await waitForGitHubPullRequestStatus(editor)

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        try await TestSupport.waitUntil("GitHub pull request refresh on activation") {
            await gitHubPullRequestService.calls().count >= 2
        }
    }

    func testGitHubPullRequestPollingDoesNotEnterLoadingState() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let pullRequest = GitHubPullRequestInfo(
            number: 42,
            url: URL(string: "https://github.com/owner/repo/pull/42")!,
            lifecycleState: .open,
            mergeableState: .mergeable
        )
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(
            pullRequests: [
                rootURL.standardizedFileURL: [
                    "feature/status-pr": .pullRequest(pullRequest)
                ]
            ],
            responseDelayNanoseconds: 100_000_000
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch("feature/status-pr")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false,
            githubPullRequestPollingIntervalNanoseconds: 20_000_000,
            isApplicationActive: { true }
        )

        await editor.openProject(rootURL)
        _ = try await waitForGitHubPullRequestStatus(editor)

        // 2回目以降(ポーリング)の取得中も Loading にならず、前回の表示を保持する。
        try await TestSupport.waitUntil("GitHub pull request polling call") {
            await gitHubPullRequestService.calls().count >= 2
        }
        XCTAssertFalse(editor.githubPullRequestLoadingProjectIDs.contains(rootURL.standardizedFileURL))
        XCTAssertEqual(editor.githubPullRequestStatus, .pullRequest(pullRequest))
    }

    func testGitHubPullRequestPollingPreservesDeterminateMergeableStateOnUnknown() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let pullRequestURL = URL(string: "https://github.com/owner/repo/pull/42")!
        let conflictingStatus = GitHubPullRequestStatus.pullRequest(GitHubPullRequestInfo(
            number: 42,
            url: pullRequestURL,
            lifecycleState: .open,
            mergeableState: .conflicting
        ))
        let unknownStatus = GitHubPullRequestStatus.pullRequest(GitHubPullRequestInfo(
            number: 42,
            url: pullRequestURL,
            lifecycleState: .open,
            mergeableState: .unknown
        ))
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(
            pullRequests: [:],
            statusSequence: [conflictingStatus, unknownStatus]
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(
                        rootURL: rootURL,
                        branch: .branch("feature/status-pr")
                    )
                ]
            ),
            githubPullRequestService: gitHubPullRequestService,
            isFileWatchingEnabled: false,
            githubPullRequestPollingIntervalNanoseconds: 20_000_000,
            isApplicationActive: { true }
        )

        await editor.openProject(rootURL)
        try await waitForGitHubPullRequestStatus(
            editor,
            workspaceID: rootURL.standardizedFileURL,
            expectedStatus: conflictingStatus
        )

        // 以降のポーリングは UNKNOWN を返し続けるが、確定済みの conflicting を保持する。
        try await TestSupport.waitUntil("GitHub pull request polling calls after unknown") {
            await gitHubPullRequestService.calls().count >= 3
        }
        XCTAssertEqual(editor.githubPullRequestStatus, conflictingStatus)
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
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
            worktreeURL.standardizedFileURL: [
                "feature-one": .pullRequest(pullRequest)
            ]
        ])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [
            worktreeURL.standardizedFileURL: [
                "feature-one": .create(creationLink)
            ]
        ])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(
            pullRequests: [:],
            responseDelayNanoseconds: 300_000_000
        )
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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

        let gitHubPullRequestService = EditorViewModelWorkspaceMockGitHubPullRequestService(pullRequests: [:])
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
                snapshots: [
                    rootURL.standardizedFileURL: makeGitSnapshot(rootURL: rootURL, branch: .branch("main"))
                ],
                githubRepositoryIdentitiesByRoot: [
                    rootURL.standardizedFileURL: [GitHubRepositoryIdentity(owner: "owner", name: "repo")]
                ]
            ),
            githubPullRequestService: EditorViewModelWorkspaceMockGitHubPullRequestService(
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

        try await WorktreeInitializationStore().save(
            WorktreeInitializationDocument(initializationCommand: "npm install"),
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory),
            repositoryRootURL: rootURL
        )
        let initializationService = RecordingWorktreeInitializationService()
        let editor = EditorViewModel(
            worktreeInitializationService: initializationService,
            isFileWatchingEnabled: false
        )
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

    func testConfirmExternalPullRequestWorktreeCreationIgnoresConcurrentSecondConfirmation() async throws {
        let parentURL = try makeTemporaryDirectory()
        let remoteURL = parentURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let seedURL = parentURL.appending(path: "seed", directoryHint: .isDirectory)
        let projectURL = parentURL.appending(path: "Project", directoryHint: .isDirectory)
        let rootURL = projectURL.appending(path: "repo", directoryHint: .isDirectory)
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

        let initializationService = RecordingWorktreeInitializationService()
        let editor = EditorViewModel(
            worktreeInitializationService: initializationService,
            isFileWatchingEnabled: false
        )
        await editor.openProject(rootURL)
        let request = ExternalPullRequestWorktreeCreationRequest(
            pullRequestNumber: 1,
            repository: GitHubRepositoryIdentity(owner: "owner", name: "repo"),
            headBranchName: "feature",
            remoteBranchName: "origin/feature",
            sourceWorkspaceID: rootURL
        )

        async let firstConfirmation: Void = editor.confirmExternalPullRequestWorktreeCreation(request)
        async let secondConfirmation: Void = editor.confirmExternalPullRequestWorktreeCreation(request)
        _ = await (firstConfirmation, secondConfirmation)

        XCTAssertNil(editor.errorMessage)
        XCTAssertFalse(editor.isCreatingExternalPullRequestWorktree)
        XCTAssertEqual(
            editor.projectWorkspaces.filter { $0.url.lastPathComponent == "feature" }.count,
            1
        )
    }

    func testPullWorktreeIgnoresSecondPullWhileFirstIsInFlight() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let gate = AsyncTestGate()
        let gitService = EditorViewModelWorkspaceMockGitService(snapshots: [:])
        gitService.pullHandler = { _ in await gate.wait() }

        let editor = EditorViewModel(gitService: gitService, isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        let workspaceID = try XCTUnwrap(editor.activeProjectID)

        let firstPull = Task { @MainActor in
            try await editor.pullWorktree(workspaceID)
        }
        try await waitUntil { gitService.pullCalls().count == 1 }
        XCTAssertTrue(editor.pullingWorkspaceIDs.contains(workspaceID))

        let secondResult = try await editor.pullWorktree(workspaceID)

        XCTAssertFalse(secondResult)
        XCTAssertEqual(gitService.pullCalls().count, 1)

        await gate.open()
        let firstResult = try await firstPull.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(editor.pullingWorkspaceIDs.isEmpty)
    }

    func testPullWorktreeAllowsConcurrentPullsOnDifferentWorkspaces() async throws {
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
        let gate = AsyncTestGate()
        let gitService = EditorViewModelWorkspaceMockGitService(
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
                    branch: .branch("feature-one"),
                    worktreeKind: .linked,
                    worktreeRootURLs: [baseURL, worktreeURL],
                    worktrees: worktrees,
                    gitDirectoryURL: commonGitDirectoryURL
                        .appending(path: "worktrees/feature-one", directoryHint: .isDirectory),
                    gitCommonDirectoryURL: commonGitDirectoryURL
                )
            ]
        )
        gitService.pullHandler = { _ in await gate.wait() }

        let editor = EditorViewModel(gitService: gitService, isFileWatchingEnabled: false)
        await editor.openProject(baseURL)
        let baseID = try XCTUnwrap(editor.activeProjectID)
        let worktreeID = try XCTUnwrap(
            editor.projectWorkspaces.first { $0.id != baseID }?.id
        )

        let basePull = Task { @MainActor in
            try await editor.pullWorktree(baseID)
        }
        let worktreePull = Task { @MainActor in
            try await editor.pullWorktree(worktreeID)
        }
        try await waitUntil { gitService.pullCalls().count == 2 }

        XCTAssertEqual(editor.pullingWorkspaceIDs, [baseID, worktreeID])

        await gate.open()
        let baseResult = try await basePull.value
        let worktreeResult = try await worktreePull.value

        XCTAssertTrue(baseResult)
        XCTAssertTrue(worktreeResult)
        XCTAssertTrue(editor.pullingWorkspaceIDs.isEmpty)
    }

    func testPullWorktreeClearsPullingStateWhenPullThrows() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let gitService = EditorViewModelWorkspaceMockGitService(snapshots: [:])
        gitService.pullHandler = { _ in throw GitPullError.timedOut }

        let editor = EditorViewModel(gitService: gitService, isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        let workspaceID = try XCTUnwrap(editor.activeProjectID)

        do {
            try await editor.pullWorktree(workspaceID)
            XCTFail("Expected pullWorktree to rethrow the pull error")
        } catch GitPullError.timedOut {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(editor.pullingWorkspaceIDs.isEmpty)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                throw CancellationError()
            }
            await Task.yield()
        }
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
        let gitService = RecordingEditorViewModelWorkspaceGitService(snapshots: [
            baseURL.standardizedFileURL: baseSnapshot,
            worktreeURL.standardizedFileURL: worktreeSnapshot
        ])
        let editor = EditorViewModel(gitService: gitService, isFileWatchingEnabled: false)

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
        let gitService = RecordingEditorViewModelWorkspaceGitService(snapshots: [
            baseURL.standardizedFileURL: baseSnapshot,
            worktreeURL.standardizedFileURL: worktreeSnapshot
        ])
        let editor = EditorViewModel(gitService: gitService, isFileWatchingEnabled: false)

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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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

        let definitionURL = worktreeURL.appending(path: "Definition.java")
        let usageURL = worktreeURL.appending(path: "Usage.java")
        let definitionText = "class Target {}\n"
        let usageText = "class Usage { Target target; }\n"
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
                    oldRelativePath: "Usage.java",
                    newRelativePath: "Usage.java",
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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

        let definitionURL = worktreeURL.appending(path: "Definition.java")
        let usageURL = worktreeURL.appending(path: "Usage.java")
        let definitionText = "class Target {}\n"
        let oldUsageText = "class Usage { Target target; }\n"
        let currentUsageText = "class Usage { CurrentOnly current; }\n"
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
                    oldRelativePath: "Usage.java",
                    newRelativePath: "Usage.java",
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
        let editor = EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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
                            "Usage.java": oldUsageText
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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
        let editor = EditorViewModel(
            worktreeInitializationService: initializationService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        let workspaceID = try await editor.createWorktree(named: "feature-one")
        try await editor.initializeCreatedWorktree(workspaceID, command: "npm install")

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
        let editor = EditorViewModel(
            worktreeInitializationService: initializationService,
            isFileWatchingEnabled: false
        )

        await editor.openProject(rootURL)
        let workspaceID = try await editor.createWorktree(named: "feature-one")

        do {
            try await editor.initializeCreatedWorktree(workspaceID, command: "npm install")
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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
        let branches = try runGit(["branch", "--list", "linked"], in: rootURL)
        XCTAssertTrue(branches.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel()

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

        let editor = EditorViewModel()

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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
        let sourceDirectoryURL = rootURL.appending(path: "src/main/java", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = sourceDirectoryURL.appending(path: "Source.java")
        let targetURL = sourceDirectoryURL.appending(path: "Target.java")
        let sourceText = "class Source {\n    Target target;\n}\n"
        let targetText = "class Target {}\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try targetText.write(to: targetURL, atomically: true, encoding: .utf8)

        let targetRange = (targetText as NSString).range(of: "Target")
        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

    func testContextualCodeNavigationNavigatesWhenDefinitionHasSingleReference() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "".write(to: rootURL.appending(path: "settings.gradle.kts"), atomically: true, encoding: .utf8)
        let sourceDirectoryURL = rootURL.appending(path: "src/main/java", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = sourceDirectoryURL.appending(path: "Source.java")
        let savedText = "class Target {}\nclass Source { Target target; }\n"
        let unsavedText = "class Target {}\nclass Source { Target editedTarget; }\n"
        try savedText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        try await waitForSymbolIndexReady(editor)
        await editor.openFile(sourceURL)
        let sourceTabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateText(unsavedText, in: sourceTabID)

        let navigationResult = await editor.resolveImplementationOrReferences(at: 6, in: sourceTabID)
        guard case .navigated(let closedDocument) = navigationResult else {
            return XCTFail("Expected single reference definition click to navigate directly.")
        }

        XCTAssertNil(closedDocument)
        let selectedTabID = try XCTUnwrap(editor.selectedTabID)
        let selectedTab = try XCTUnwrap(editor.tab(for: selectedTabID))
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedTab.url, sourceURL))

        let session = try XCTUnwrap(editor.editorSession(for: selectedTabID))
        let usageRange = (unsavedText as NSString).range(of: "Target editedTarget")
        XCTAssertTrue(NSEqualRanges(session.selectedRange, NSRange(location: usageRange.location, length: 6)))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    func testCodeUsageJumpPreservesSourceTabAndRecordsHistory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Definition.java")
        let usageURL = rootURL.appending(path: "Usage.java")
        let sourceText = "class Target {}\n"
        let usageText = "class Usage { Target target; }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try usageText.write(to: usageURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(sourceURL)
        let sourceTabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateSelection(NSRange(location: 6, length: 0), in: sourceTabID)

        let usageRange = TextRange(location: (usageText as NSString).range(of: "Target").location, length: 6)
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

    func testNavigationHistoryRestoresEditorPlaceAcrossReviewModeSwitch() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "First.txt")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = makeReviewCapableEditor(rootURL: rootURL)

        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)
        let originRange = NSRange(location: 0, length: 5)
        editor.updateSelection(originRange, in: tabID)

        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)
        XCTAssertTrue(editor.canNavigateBack)

        await editor.navigateBackInHistory()

        XCTAssertEqual(editor.editorMode, .edit)
        let backSession = try XCTUnwrap(editor.editorSession(for: tabID))
        XCTAssertTrue(NSEqualRanges(backSession.selectedRange, originRange))
        XCTAssertTrue(editor.canNavigateForward)

        await editor.navigateForwardInHistory()

        XCTAssertEqual(editor.editorMode, .review)
    }

    func testOpeningFileFromReviewModeRecordsReviewPlace() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appending(path: "First.txt")
        let secondFileURL = rootURL.appending(path: "Second.txt")
        try "first".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondFileURL, atomically: true, encoding: .utf8)

        let editor = makeReviewCapableEditor(rootURL: rootURL)

        await editor.openProject(rootURL)
        await editor.openFile(firstFileURL)
        editor.setEditorMode(.review)
        _ = try await waitForReviewDiffLoaded(editor)

        await editor.openFile(secondFileURL)

        XCTAssertEqual(editor.editorMode, .edit)
        let openedTab = try XCTUnwrap(editor.selectedTabID.flatMap { editor.tab(for: $0) })
        XCTAssertTrue(FileURLRewriter.urlsMatch(openedTab.url, secondFileURL))

        await editor.navigateBackInHistory()
        XCTAssertEqual(editor.editorMode, .review)

        await editor.navigateBackInHistory()
        XCTAssertEqual(editor.editorMode, .edit)
        let firstTab = try XCTUnwrap(editor.selectedTabID.flatMap { editor.tab(for: $0) })
        XCTAssertTrue(FileURLRewriter.urlsMatch(firstTab.url, firstFileURL))

        await editor.navigateForwardInHistory()
        XCTAssertEqual(editor.editorMode, .review)

        await editor.navigateForwardInHistory()
        XCTAssertEqual(editor.editorMode, .edit)
        let secondTab = try XCTUnwrap(editor.selectedTabID.flatMap { editor.tab(for: $0) })
        XCTAssertTrue(FileURLRewriter.urlsMatch(secondTab.url, secondFileURL))
    }

    func testFailedReviewModeSwitchDoesNotRecordNavigationHistory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "First.txt")
        try "first".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        XCTAssertFalse(editor.canNavigateBack)

        editor.setEditorMode(.review)

        XCTAssertEqual(editor.editorMode, .edit)
        XCTAssertFalse(editor.canNavigateBack)
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)

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

        let editor = EditorViewModel()

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

        let editor = EditorViewModel()
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)

        editor.revealRange(NSRange(location: 6, length: 6), in: tabID)

        let session = try XCTUnwrap(editor.editorSession(for: tabID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, NSRange(location: 6, length: 6)))
        XCTAssertNotNil(session.pendingSelectionRevealID)
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }

    private func initializeRepository(at rootURL: URL) throws {
        try TestSupport.initializeRepository(at: rootURL, fileManager: fileManager)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in rootURL: URL) throws -> String {
        try TestSupport.runGit(arguments, in: rootURL, fileManager: fileManager)
    }

    private func waitForSymbolIndexReady(
        _ editor: EditorViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await TestSupport.waitUntil("symbol index readiness", file: file, line: line) {
            if case .ready = editor.symbolIndexStatus {
                return true
            }

            return false
        }
    }

    private func waitForReviewDiffLoaded(
        _ editor: EditorViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> GitReviewDiffSnapshot {
        var loadedSnapshot: GitReviewDiffSnapshot?
        try await TestSupport.waitUntil("review diff", file: file, line: line) {
            if case .loaded(let snapshot) = editor.reviewDiffState {
                loadedSnapshot = snapshot
                return true
            }

            return false
        }
        return try XCTUnwrap(loadedSnapshot, file: file, line: line)
    }

    private func waitForReviewDiffCallCount(
        _ expectedCount: Int,
        in gitService: EditorViewModelWorkspaceMockGitService,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [EditorViewModelWorkspaceMockGitService.ReviewDiffCall] {
        var matchedCalls: [EditorViewModelWorkspaceMockGitService.ReviewDiffCall] = []
        try await TestSupport.waitUntil("review diff calls", file: file, line: line) {
            let calls = gitService.reviewDiffCalls()
            if calls.count >= expectedCount {
                matchedCalls = calls
                return true
            }

            return false
        }
        return matchedCalls
    }

    private func waitForReviewBase(
        _ editor: EditorViewModel,
        _ expectedBase: GitReviewDiffBase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await TestSupport.waitUntil("review base", file: file, line: line) {
            editor.reviewDiffBase == expectedBase
        }
    }

    private func waitForStoredReviewBase(
        _ expectedBase: GitReviewDiffBase,
        branchName: String,
        metadataDirectoryURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let store = WorktreeMetadataStore()
        try await TestSupport.waitUntil("stored review base", file: file, line: line) {
            await store.reviewBase(forBranch: branchName, metadataDirectoryURL: metadataDirectoryURL) == expectedBase
        }
    }

    private func waitForGitHubPullRequestStatus(
        _ editor: EditorViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> GitHubPullRequestStatus {
        var loadedStatus: GitHubPullRequestStatus?
        try await TestSupport.waitUntil("GitHub pull request", file: file, line: line) {
            if let status = editor.githubPullRequestStatus {
                loadedStatus = status
                return true
            }

            return false
        }
        return try XCTUnwrap(loadedStatus, file: file, line: line)
    }

    private func waitForGitHubPullRequestStatus(
        _ editor: EditorViewModel,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        expectedStatus: GitHubPullRequestStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let workspaceID = workspaceID.standardizedFileURL
        try await TestSupport.waitUntil("workspace GitHub pull request", file: file, line: line) {
            editor.githubPullRequestStatusesByProjectID[workspaceID] == expectedStatus
        }
    }

    private func waitForGitHubPullRequestLoadingState(
        _ editor: EditorViewModel,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        isLoading: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let workspaceID = workspaceID.standardizedFileURL
        try await TestSupport.waitUntil("workspace GitHub pull request loading state", file: file, line: line) {
            editor.githubPullRequestLoadingProjectIDs.contains(workspaceID) == isLoading
        }
    }

    private func waitForGitHubPullRequestCall(
        _ service: EditorViewModelWorkspaceMockGitHubPullRequestService,
        branchName: String,
        baseBranchName: String?,
        openedRootURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> EditorViewModelWorkspaceMockGitHubPullRequestService.Call {
        let expectedCall = EditorViewModelWorkspaceMockGitHubPullRequestService.Call(
            branchName: branchName,
            baseBranchName: baseBranchName,
            openedRootURL: openedRootURL.standardizedFileURL
        )
        var matchedCall: EditorViewModelWorkspaceMockGitHubPullRequestService.Call?
        try await TestSupport.waitUntil("GitHub pull request lookup", file: file, line: line) {
            if let call = await service.calls().first(where: { $0 == expectedCall }) {
                matchedCall = call
                return true
            }

            return false
        }
        return try XCTUnwrap(matchedCall, file: file, line: line)
    }

    private func makeReviewFileDiff(path: String, contentFingerprint: String?) -> GitReviewFileDiff {
        GitReviewFileDiff(
            diff: SourceFileDiff(
                oldRelativePath: path,
                newRelativePath: path,
                hunks: [
                    SourceDiffHunk(
                        oldStart: 1,
                        oldLineCount: 1,
                        newStart: 1,
                        newLineCount: 1,
                        lines: [
                            SourceDiffLine(kind: .deletion, oldLineNumber: 1, newLineNumber: nil, content: "old"),
                            SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, content: "new")
                        ]
                    )
                ]
            ),
            contentFingerprint: contentFingerprint
        )
    }

    private func makeReviewCapableEditor(rootURL: URL) -> EditorViewModel {
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

        return EditorViewModel(
            gitService: EditorViewModelWorkspaceMockGitService(
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

private actor EditorViewModelWorkspaceMockGitHubPullRequestFileViewsService: GitHubPullRequestFileViewsServiceProtocol {
    struct SetCall: Equatable {
        let viewed: Bool
        let pullRequestNodeID: String
        let path: String
        let openedRootURL: URL
    }

    private let result: GitHubPullRequestFileViewsResult
    private let setError: Error?
    private let fileViewsDelayNanoseconds: UInt64
    private var storedSetCalls: [SetCall] = []

    init(
        result: GitHubPullRequestFileViewsResult,
        setError: Error? = nil,
        fileViewsDelayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.setError = setError
        self.fileViewsDelayNanoseconds = fileViewsDelayNanoseconds
    }

    func fileViews(
        pullRequestNumber: Int,
        openedRootURL: URL
    ) async -> GitHubPullRequestFileViewsResult {
        if fileViewsDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: fileViewsDelayNanoseconds)
        }
        return result
    }

    func setFileViewed(
        _ viewed: Bool,
        pullRequestNodeID: String,
        path: String,
        openedRootURL: URL
    ) async throws {
        storedSetCalls.append(SetCall(
            viewed: viewed,
            pullRequestNodeID: pullRequestNodeID,
            path: path,
            openedRootURL: openedRootURL
        ))
        if let setError {
            throw setError
        }
    }

    func setCalls() -> [SetCall] {
        storedSetCalls
    }
}

private actor EditorViewModelWorkspaceMockGitHubPullRequestService: GitHubPullRequestServiceProtocol {
    struct Call: Equatable {
        let branchName: String
        let baseBranchName: String?
        let openedRootURL: URL
    }

    private let pullRequests: [URL: [String: GitHubPullRequestStatus]]
    private let pullRequestDetailsByRootAndNumber: [URL: [Int: GitHubPullRequestDetails]]
    private let responseDelayNanoseconds: UInt64
    private var statusSequence: [GitHubPullRequestStatus?]
    private var storedCalls: [Call] = []

    init(
        pullRequests: [URL: [String: GitHubPullRequestStatus]],
        pullRequestDetailsByRootAndNumber: [URL: [Int: GitHubPullRequestDetails]] = [:],
        responseDelayNanoseconds: UInt64 = 0,
        statusSequence: [GitHubPullRequestStatus?] = []
    ) {
        self.pullRequests = pullRequests.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
        self.pullRequestDetailsByRootAndNumber = pullRequestDetailsByRootAndNumber.reduce(into: [:]) { result, entry in
            result[entry.key.standardizedFileURL] = entry.value
        }
        self.responseDelayNanoseconds = responseDelayNanoseconds
        self.statusSequence = statusSequence
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
        if !statusSequence.isEmpty {
            // 最後の要素は以降の呼び出しでも返し続ける。
            return statusSequence.count > 1 ? statusSequence.removeFirst() : statusSequence[0]
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

private actor AsyncTestGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        isOpen = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }
}

nonisolated private final class EditorViewModelWorkspaceMockGitService: GitServiceProtocol, @unchecked Sendable {
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
    var pullHandler: (@Sendable (URL) async throws -> Void)?
    private let lock = NSLock()
    private var storedReviewDiffCalls: [ReviewDiffCall] = []
    private var storedReviewDiffUpdateCalls: [ReviewDiffUpdateCall] = []
    private var storedPullCalls: [URL] = []

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

    func pull(openedRootURL: URL) async throws {
        let openedRootURL = openedRootURL.standardizedFileURL
        lock.lock()
        storedPullCalls.append(openedRootURL)
        lock.unlock()

        try await pullHandler?(openedRootURL)
    }

    func pullCalls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedPullCalls
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

nonisolated private final class RecordingEditorViewModelWorkspaceGitService: GitServiceProtocol, @unchecked Sendable {
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
