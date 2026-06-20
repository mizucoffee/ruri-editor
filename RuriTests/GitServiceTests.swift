//
//  GitServiceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class GitServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSnapshotReportsBranchChangesAndDiffs() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let trackedURL = rootURL.appending(path: "Tracked.txt")
        let untrackedURL = rootURL.appending(path: "Untracked.txt")

        try "one\ntwo\nthree\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)

        try "one\ntwo edited\nthree\nfour\n".write(to: trackedURL, atomically: true, encoding: .utf8)
        try "new\nfile\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        let optionalSnapshot = await GitService().snapshot(for: rootURL)
        let snapshot = try XCTUnwrap(optionalSnapshot)

        XCTAssertEqual(snapshot.branch.displayName, "main")
        XCTAssertEqual(snapshot.worktreeKind, .main)
        XCTAssertFalse(snapshot.hasOtherWorktrees)
        XCTAssertEqual(snapshot.change(for: trackedURL)?.displayStatus, .modified)
        XCTAssertEqual(snapshot.change(for: untrackedURL)?.displayStatus, .untracked)

        XCTAssertEqual(
            snapshot.diff(for: trackedURL)?.editorDecorations,
            [
                EditorDiffDecoration(lineNumber: 2, kind: .modified),
                EditorDiffDecoration(lineNumber: 4, kind: .added)
            ]
        )
        XCTAssertEqual(
            snapshot.diff(for: untrackedURL)?.editorDecorations,
            [
                EditorDiffDecoration(lineNumber: 1, kind: .added),
                EditorDiffDecoration(lineNumber: 2, kind: .added)
            ]
        )
    }

    func testSnapshotFiltersChangesToOpenedSubdirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let appURL = rootURL.appending(path: "App", directoryHint: .isDirectory)
        let docsURL = rootURL.appending(path: "Docs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let appFileURL = appURL.appending(path: "Feature.swift")
        let docsFileURL = docsURL.appending(path: "Guide.md")
        try "feature\n".write(to: appFileURL, atomically: true, encoding: .utf8)
        try "guide\n".write(to: docsFileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)

        try "feature edited\n".write(to: appFileURL, atomically: true, encoding: .utf8)
        try "guide edited\n".write(to: docsFileURL, atomically: true, encoding: .utf8)

        let optionalSnapshot = await GitService().snapshot(for: appURL)
        let snapshot = try XCTUnwrap(optionalSnapshot)

        XCTAssertNotNil(snapshot.change(for: appFileURL))
        XCTAssertNil(snapshot.change(for: docsFileURL))
        XCTAssertNotNil(snapshot.diff(for: appFileURL))
        XCTAssertNil(snapshot.diff(for: docsFileURL))
    }

    func testFileSnapshotReportsTrackedDiff() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Tracked.txt")
        try "one\ntwo\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)

        try "one\ntwo edited\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let optionalFileSnapshot = await GitService().fileSnapshot(for: fileURL, openedRootURL: rootURL)
        let fileSnapshot = try XCTUnwrap(optionalFileSnapshot)

        XCTAssertEqual(fileSnapshot.change?.displayStatus, .modified)
        XCTAssertEqual(fileSnapshot.diff?.editorDecorations, [
            EditorDiffDecoration(lineNumber: 2, kind: .modified),
            EditorDiffDecoration(lineNumber: 3, kind: .added)
        ])
    }

    func testFileSnapshotReportsCleanFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Tracked.txt")
        try "one\ntwo\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)

        let optionalFileSnapshot = await GitService().fileSnapshot(for: fileURL, openedRootURL: rootURL)
        let fileSnapshot = try XCTUnwrap(optionalFileSnapshot)

        XCTAssertNil(fileSnapshot.change)
        XCTAssertNil(fileSnapshot.diff)
    }

    func testFileContentsReadsUTF8FileAtRevision() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Tracked.txt")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        let revision = try runGit(["rev-parse", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try "current\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let contents = try await GitService().fileContents(
            at: revision,
            relativePath: "Tracked.txt",
            openedRootURL: rootURL
        )

        XCTAssertEqual(contents, "base\n")
    }

    func testFileSnapshotReportsUntrackedSyntheticDiff() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Untracked.txt")
        try "new\nfile\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let optionalFileSnapshot = await GitService().fileSnapshot(for: fileURL, openedRootURL: rootURL)
        let fileSnapshot = try XCTUnwrap(optionalFileSnapshot)

        XCTAssertEqual(fileSnapshot.change?.displayStatus, .untracked)
        XCTAssertEqual(fileSnapshot.diff?.editorDecorations, [
            EditorDiffDecoration(lineNumber: 1, kind: .added),
            EditorDiffDecoration(lineNumber: 2, kind: .added)
        ])
    }

    func testDiffParserDoesNotTreatChangedContentAsFileHeaders() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Markers.txt")
        try "-- old\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Markers.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)

        try "++ new\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let optionalSnapshot = await GitService().snapshot(for: rootURL)
        let snapshot = try XCTUnwrap(optionalSnapshot)

        XCTAssertEqual(snapshot.diff(for: fileURL)?.displayRelativePath, "Markers.txt")
        XCTAssertEqual(snapshot.diff(for: fileURL)?.editorDecorations, [
            EditorDiffDecoration(lineNumber: 1, kind: .modified)
        ])
    }

    func testNonGitDirectoryReturnsNilSnapshot() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let status = await GitService().repositoryStatus(for: rootURL)
        let snapshot = await GitService().snapshot(for: rootURL)

        XCTAssertEqual(status, .notRepository(rootURL.standardizedFileURL))
        XCTAssertNil(snapshot)
    }

    func testRepositoryStatusReportsMainWorktree() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)

        let status = await GitService().repositoryStatus(for: rootURL)
        guard case .repository(let snapshot) = status else {
            return XCTFail("Expected repository status")
        }

        XCTAssertEqual(snapshot.worktreeKind, .main)
        XCTAssertFalse(snapshot.hasOtherWorktrees)
        XCTAssertEqual(snapshot.worktreeRootURLs.count, 1)
        XCTAssertTrue(FileURLRewriter.urlsMatch(snapshot.worktreeRootURL, rootURL))
        XCTAssertTrue(FileURLRewriter.urlsMatch(snapshot.gitDirectoryURL, snapshot.gitCommonDirectoryURL))
    }

    func testRepositoryStatusMarksRuriBaseAsRuriStyleWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "tracked\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        try runGit(["branch", "feature/sidebar"], in: rootURL)

        let status = await GitService().repositoryStatus(for: rootURL)
        guard case .repository(let snapshot) = status else {
            return XCTFail("Expected repository status")
        }

        XCTAssertTrue(snapshot.isRuriStyleWorktree)
        XCTAssertEqual(snapshot.localBranches.map(\.name), ["feature/sidebar", "main"])
        XCTAssertTrue(FileURLRewriter.urlsMatch(
            try XCTUnwrap(snapshot.localBranches.first { $0.name == "main" }?.checkedOutWorktreeURL),
            rootURL
        ))
    }

    func testRepositoryStatusDoesNotMarkRegularRootAsRuriStyleWorktree() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)

        let status = await GitService().repositoryStatus(for: rootURL)
        guard case .repository(let snapshot) = status else {
            return XCTFail("Expected repository status")
        }

        XCTAssertFalse(snapshot.isRuriStyleWorktree)
    }

    func testRepositoryStatusReportsLinkedWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "repo-linked", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Tracked.txt")
        try "tracked\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        try runGit(["worktree", "add", "-b", "linked", worktreeURL.path(percentEncoded: false)], in: rootURL)

        let rootStatus = await GitService().repositoryStatus(for: rootURL)
        guard case .repository(let rootSnapshot) = rootStatus else {
            return XCTFail("Expected root repository status")
        }

        XCTAssertEqual(rootSnapshot.worktreeKind, .main)
        XCTAssertTrue(rootSnapshot.hasOtherWorktrees)
        XCTAssertEqual(rootSnapshot.worktreeRootURLs.count, 2)
        XCTAssertEqual(rootSnapshot.worktrees.map(\.displayName), ["main", "linked"])

        let status = await GitService().repositoryStatus(for: worktreeURL)
        guard case .repository(let snapshot) = status else {
            return XCTFail("Expected repository status")
        }

        XCTAssertEqual(snapshot.worktreeKind, .linked)
        XCTAssertTrue(snapshot.hasOtherWorktrees)
        XCTAssertEqual(snapshot.worktreeRootURLs.count, 2)
        XCTAssertEqual(snapshot.worktrees.map(\.displayName), ["main", "linked"])
        XCTAssertTrue(FileURLRewriter.urlsMatch(snapshot.worktreeRootURL, worktreeURL))
        XCTAssertFalse(FileURLRewriter.urlsMatch(snapshot.gitDirectoryURL, snapshot.gitCommonDirectoryURL))
        XCTAssertEqual(snapshot.branch.displayName, "linked")
    }

    func testSwitchBranchSwitchesRuriBaseWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
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

        try await GitService().switchBranch(named: "feature/sidebar", openedRootURL: rootURL)

        XCTAssertEqual(
            try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: rootURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feature/sidebar"
        )
        XCTAssertEqual(
            try String(contentsOf: rootURL.appending(path: "Tracked.txt"), encoding: .utf8),
            "feature\n"
        )
    }

    func testSwitchBranchFailsWhenBranchIsCheckedOutInAnotherWorktree() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "feature-sidebar", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "main\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "main"], in: rootURL)
        try runGit(["branch", "feature/sidebar"], in: rootURL)
        try runGit(["worktree", "add", worktreeURL.path(percentEncoded: false), "feature/sidebar"], in: rootURL)

        do {
            try await GitService().switchBranch(named: "feature/sidebar", openedRootURL: rootURL)
            XCTFail("Expected branch switch to fail")
        } catch GitBranchSwitchError.branchAlreadyCheckedOut(let branchName, let checkedOutURL) {
            XCTAssertEqual(branchName, "feature/sidebar")
            XCTAssertTrue(FileURLRewriter.urlsMatch(checkedOutURL, worktreeURL))
        }
    }

    func testReviewDiffIncludesCommittedStagedUnstagedAndUntrackedChanges() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "feature-review", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "one\ntwo\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        try runGit(["worktree", "add", "-b", "feature/review", worktreeURL.path(percentEncoded: false)], in: rootURL)

        try "one\ntwo feature\nthree\n".write(to: worktreeURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "feature commit"], in: worktreeURL)
        try "one\ntwo feature\nthree dirty\n".write(to: worktreeURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try "staged\n".write(to: worktreeURL.appending(path: "Staged.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Staged.txt"], in: worktreeURL)
        try "new\nfile\n".write(to: worktreeURL.appending(path: "Untracked.txt"), atomically: true, encoding: .utf8)

        let snapshot = try await GitService().reviewDiff(baseBranch: "main", openedRootURL: worktreeURL)

        XCTAssertEqual(snapshot.baseBranch, "main")
        XCTAssertEqual(snapshot.targetBranch.displayName, "feature/review")
        XCTAssertEqual(snapshot.files.map(\.displayRelativePath), [
            "Staged.txt",
            "Tracked.txt",
            "Untracked.txt"
        ])
        XCTAssertEqual(snapshot.files.first { $0.displayRelativePath == "Staged.txt" }?.status, .added)
        XCTAssertEqual(snapshot.files.first { $0.displayRelativePath == "Untracked.txt" }?.status, .untracked)
        XCTAssertTrue(snapshot.files.contains { file in
            file.diff.hunks.flatMap(\.lines).contains { $0.content == "three dirty" }
        })
        XCTAssertTrue(snapshot.files.contains { file in
            file.diff.hunks.flatMap(\.lines).contains { $0.content == "new" }
        })
    }

    func testReviewDiffCanHideWhitespaceOnlyChanges() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        try "let value = 1\n".write(to: rootURL.appending(path: "Spacing.txt"), atomically: true, encoding: .utf8)
        try "alpha\nbeta\n".write(to: rootURL.appending(path: "BlankLines.txt"), atomically: true, encoding: .utf8)
        try "old\n".write(to: rootURL.appending(path: "RealChange.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Spacing.txt", "BlankLines.txt", "RealChange.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        try "let   value = 1\n".write(to: rootURL.appending(path: "Spacing.txt"), atomically: true, encoding: .utf8)
        try "alpha\n\nbeta\n".write(to: rootURL.appending(path: "BlankLines.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: rootURL.appending(path: "RealChange.txt"), atomically: true, encoding: .utf8)

        let defaultSnapshot = try await GitService().reviewDiff(base: .uncommitted, openedRootURL: rootURL)
        let hiddenSnapshot = try await GitService().reviewDiff(
            base: .uncommitted,
            options: GitReviewDiffOptions(hideWhitespace: true),
            openedRootURL: rootURL
        )

        XCTAssertEqual(defaultSnapshot.files.map(\.displayRelativePath), [
            "BlankLines.txt",
            "RealChange.txt",
            "Spacing.txt"
        ])
        XCTAssertEqual(hiddenSnapshot.files.map(\.displayRelativePath), ["RealChange.txt"])
        XCTAssertTrue(hiddenSnapshot.files[0].diff.hunks.flatMap(\.lines).contains { $0.content == "new" })
    }

    func testReviewDiffUpdateOnlyIncludesRequestedFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let firstURL = rootURL.appending(path: "First.txt")
        let secondURL = rootURL.appending(path: "Second.txt")
        try "one\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "two\n".write(to: secondURL, atomically: true, encoding: .utf8)
        try runGit(["add", "First.txt", "Second.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        try "one changed\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "two changed\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let update = try await GitService().reviewDiffUpdate(
            base: .uncommitted,
            options: .default,
            fileURLs: [firstURL],
            openedRootURL: rootURL
        )

        XCTAssertEqual(update.requestedRelativePaths, ["First.txt"])
        XCTAssertEqual(update.files.map(\.displayRelativePath), ["First.txt"])
        XCTAssertTrue(update.files[0].diff.hunks.flatMap(\.lines).contains { $0.content == "one changed" })
        XCTAssertFalse(update.files[0].diff.hunks.flatMap(\.lines).contains { $0.content == "two changed" })
    }

    func testReviewDiffUpdateRemovesCleanedFileWhenApplied() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        let fileURL = rootURL.appending(path: "Cleaned.txt")
        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "Cleaned.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        try "dirty\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let dirtySnapshot = try await GitService().reviewDiff(
            base: .uncommitted,
            options: .default,
            openedRootURL: rootURL
        )
        XCTAssertEqual(dirtySnapshot.files.map(\.displayRelativePath), ["Cleaned.txt"])

        try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let update = try await GitService().reviewDiffUpdate(
            base: .uncommitted,
            options: .default,
            fileURLs: [fileURL],
            openedRootURL: rootURL
        )
        let updatedSnapshot = try XCTUnwrap(dirtySnapshot.applying(update))

        XCTAssertEqual(update.files, [])
        XCTAssertEqual(updatedSnapshot.files, [])
    }

    func testReviewDiffUsesMergeBaseInsteadOfBaseBranchTip() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = parentURL
            .appending(path: "Project", directoryHint: .isDirectory)
            .appending(path: "feature-review", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)
        try runGit(["worktree", "add", "-b", "feature/review", worktreeURL.path(percentEncoded: false)], in: rootURL)

        try "base side\n".write(to: rootURL.appending(path: "MainOnly.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "MainOnly.txt"], in: rootURL)
        try runGit(["commit", "-m", "base side"], in: rootURL)

        try "feature side\n".write(to: worktreeURL.appending(path: "FeatureOnly.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "FeatureOnly.txt"], in: worktreeURL)
        try runGit(["commit", "-m", "feature side"], in: worktreeURL)

        let snapshot = try await GitService().reviewDiff(baseBranch: "main", openedRootURL: worktreeURL)

        XCTAssertEqual(snapshot.files.map(\.displayRelativePath), ["FeatureOnly.txt"])
    }

    func testReviewDiffUncommittedBaseExcludesCommittedChanges() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        try "committed\n".write(to: rootURL.appending(path: "Committed.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Committed.txt"], in: rootURL)
        try runGit(["commit", "-m", "committed"], in: rootURL)

        try "dirty\n".write(to: rootURL.appending(path: "Dirty.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Dirty.txt"], in: rootURL)
        try "base dirty\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try "untracked\n".write(to: rootURL.appending(path: "Untracked.txt"), atomically: true, encoding: .utf8)

        let snapshot = try await GitService().reviewDiff(base: .uncommitted, openedRootURL: rootURL)

        XCTAssertEqual(snapshot.base, .uncommitted)
        XCTAssertEqual(snapshot.files.map(\.displayRelativePath), [
            "Dirty.txt",
            "Tracked.txt",
            "Untracked.txt"
        ])
        XCTAssertFalse(snapshot.files.contains { $0.displayRelativePath == "Committed.txt" })
    }

    func testReviewDiffCanUseRemoteTrackingBranchBase() async throws {
        let fixture = try makeRemoteBackedRuriBaseFixture()
        defer { try? fileManager.removeItem(at: fixture.parentURL) }

        try pushRemoteOnlyCommit(from: fixture.seedURL)
        try runGit(["fetch", "origin"], in: fixture.rootURL)
        try "local\n".write(to: fixture.rootURL.appending(path: "Local.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Local.txt"], in: fixture.rootURL)
        try runGit(["commit", "-m", "local"], in: fixture.rootURL)

        let snapshot = try await GitService().reviewDiff(base: .branch("origin/main"), openedRootURL: fixture.rootURL)

        XCTAssertEqual(snapshot.base, .branch("origin/main"))
        XCTAssertEqual(snapshot.files.map(\.displayRelativePath), ["Local.txt"])
    }

    func testCreateWorktreeCreatesBranchFromRequestedBaseAtSiblingPath() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)
        try runGit(["branch", "ruri-base"], in: rootURL)
        try "main only\n".write(to: rootURL.appending(path: "MainOnly.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "MainOnly.txt"], in: rootURL)
        try runGit(["commit", "-m", "main only"], in: rootURL)

        let worktree = try await GitService().createWorktree(
            branchName: "feature-one",
            baseBranch: "ruri-base",
            openedRootURL: rootURL
        )

        XCTAssertTrue(FileURLRewriter.urlsMatch(worktree.rootURL, worktreeURL))
        XCTAssertEqual(worktree.branch?.displayName, "feature-one")
        XCTAssertEqual(worktree.kind, .linked)
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.appending(path: "Base.txt").path(percentEncoded: false)))
        XCTAssertFalse(fileManager.fileExists(atPath: worktreeURL.appending(path: "MainOnly.txt").path(percentEncoded: false)))
        XCTAssertEqual(
            try runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: worktreeURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feature-one"
        )
    }

    func testCreateWorktreePullsCleanRuriBaseBeforeBranchCreation() async throws {
        let fixture = try makeRemoteBackedRuriBaseFixture()
        defer { try? fileManager.removeItem(at: fixture.parentURL) }

        try pushRemoteOnlyCommit(from: fixture.seedURL)

        let worktree = try await GitService().createWorktree(
            branchName: "feature-one",
            openedRootURL: fixture.rootURL
        )

        XCTAssertTrue(FileURLRewriter.urlsMatch(worktree.rootURL, fixture.worktreeURL))
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.rootURL.appending(path: "RemoteOnly.txt").path(percentEncoded: false)))
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.worktreeURL.appending(path: "RemoteOnly.txt").path(percentEncoded: false)))
    }

    func testRemoteBranchesFetchesAndExcludesRemoteHead() async throws {
        let fixture = try makeRemoteBackedRuriBaseFixture()
        defer { try? fileManager.removeItem(at: fixture.parentURL) }

        try pushRemoteBranch(named: "feature-one", from: fixture.seedURL)

        let branches = try await GitService().remoteBranches(
            openedRootURL: fixture.rootURL,
            refresh: true
        )

        XCTAssertTrue(branches.contains(GitRemoteBranchInfo(fullName: "origin/feature-one")!))
        XCTAssertFalse(branches.contains { $0.fullName == "origin/HEAD" })
    }

    func testCreateWorktreeFromRemoteBranchCreatesTrackingLocalBranch() async throws {
        let fixture = try makeRemoteBackedRuriBaseFixture()
        defer { try? fileManager.removeItem(at: fixture.parentURL) }

        try pushRemoteBranch(named: "feature-one", from: fixture.seedURL)

        let worktree = try await GitService().createWorktree(
            fromRemoteBranch: "origin/feature-one",
            openedRootURL: fixture.rootURL
        )

        XCTAssertTrue(FileURLRewriter.urlsMatch(worktree.rootURL, fixture.worktreeURL))
        XCTAssertEqual(worktree.branch?.displayName, "feature-one")
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.worktreeURL.appending(path: "RemoteBranch.txt").path(percentEncoded: false)))
        XCTAssertEqual(
            try runGit(["branch", "--show-current"], in: fixture.worktreeURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feature-one"
        )
        XCTAssertEqual(
            try runGit(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: fixture.worktreeURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "origin/feature-one"
        )
    }

    func testCreateWorktreeFromRemoteBranchFailsWhenLocalBranchExists() async throws {
        let fixture = try makeRemoteBackedRuriBaseFixture()
        defer { try? fileManager.removeItem(at: fixture.parentURL) }

        try pushRemoteBranch(named: "feature-one", from: fixture.seedURL)
        try runGit(["branch", "feature-one"], in: fixture.rootURL)

        do {
            _ = try await GitService().createWorktree(
                fromRemoteBranch: "origin/feature-one",
                openedRootURL: fixture.rootURL
            )
            XCTFail("Expected remote worktree creation to fail.")
        } catch GitWorktreeCreationError.branchAlreadyExists(let branchName) {
            XCTAssertEqual(branchName, "feature-one")
        }
    }

    func testCreateWorktreeSkipsPullWhenRuriBaseIsDirty() async throws {
        let fixture = try makeRemoteBackedRuriBaseFixture()
        defer { try? fileManager.removeItem(at: fixture.parentURL) }

        try pushRemoteOnlyCommit(from: fixture.seedURL)
        try "dirty\n".write(to: fixture.rootURL.appending(path: "Dirty.txt"), atomically: true, encoding: .utf8)

        let worktree = try await GitService().createWorktree(
            branchName: "feature-one",
            openedRootURL: fixture.rootURL
        )

        XCTAssertTrue(FileURLRewriter.urlsMatch(worktree.rootURL, fixture.worktreeURL))
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.rootURL.appending(path: "RemoteOnly.txt").path(percentEncoded: false)))
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.worktreeURL.appending(path: "RemoteOnly.txt").path(percentEncoded: false)))
    }

    func testCreateWorktreeIgnoresFailedCleanRuriBasePull() async throws {
        let parentURL = try makeTemporaryDirectory()
        let projectURL = parentURL.appending(path: "Project", directoryHint: .isDirectory)
        let rootURL = projectURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = projectURL.appending(path: "feature-one", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "base\n".write(to: rootURL.appending(path: "Base.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Base.txt"], in: rootURL)
        try runGit(["commit", "-m", "base"], in: rootURL)

        let worktree = try await GitService().createWorktree(
            branchName: "feature-one",
            openedRootURL: rootURL
        )

        XCTAssertTrue(FileURLRewriter.urlsMatch(worktree.rootURL, worktreeURL))
        XCTAssertTrue(fileManager.fileExists(atPath: worktreeURL.appending(path: "Base.txt").path(percentEncoded: false)))
    }

    func testDeleteWorktreeRemovesDirectoryAndKeepsBranch() async throws {
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
        try "dirty\n".write(to: worktreeURL.appending(path: "Untracked.txt"), atomically: true, encoding: .utf8)

        try await GitService().deleteWorktree(openedRootURL: worktreeURL)

        XCTAssertFalse(fileManager.fileExists(atPath: worktreeURL.path(percentEncoded: false)))
        XCTAssertEqual(
            try runGit(["rev-parse", "--verify", "linked"], in: rootURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            false
        )

        let worktreeList = try runGit(["worktree", "list", "--porcelain"], in: rootURL)
        XCTAssertFalse(worktreeList.contains(worktreeURL.path(percentEncoded: false)))
    }

    func testDeleteMainWorktreeFails() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try initializeRepository(at: rootURL)

        do {
            try await GitService().deleteWorktree(openedRootURL: rootURL)
            XCTFail("Expected deleting the main worktree to fail")
        } catch GitWorktreeDeletionError.cannotDeleteMainWorktree(let url) {
            XCTAssertTrue(FileURLRewriter.urlsMatch(url, rootURL))
        }
    }

    func testRepositoryStatusUsesDetachedHeadFallbackForWorktreeDisplayName() async throws {
        let parentURL = try makeTemporaryDirectory()
        let rootURL = parentURL.appending(path: "repo", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "repo-detached", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: parentURL) }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try initializeRepository(at: rootURL)
        try "tracked\n".write(to: rootURL.appending(path: "Tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.txt"], in: rootURL)
        try runGit(["commit", "-m", "initial"], in: rootURL)
        let headRevision = try runGit(["rev-parse", "HEAD"], in: rootURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["worktree", "add", "--detach", worktreeURL.path(percentEncoded: false), "HEAD"], in: rootURL)

        let status = await GitService().repositoryStatus(for: rootURL)
        guard case .repository(let snapshot) = status else {
            return XCTFail("Expected repository status")
        }

        XCTAssertEqual(snapshot.worktrees.map(\.displayName), ["main", String(headRevision.prefix(7))])
    }

    func testDeletedOnlyDiffCreatesDeletedDecoration() {
        let diff = SourceFileDiff(
            oldRelativePath: "Deleted.txt",
            newRelativePath: nil,
            hunks: [
                SourceDiffHunk(
                    oldStart: 1,
                    oldLineCount: 1,
                    newStart: 0,
                    newLineCount: 0,
                    lines: [
                        SourceDiffLine(
                            kind: .deletion,
                            oldLineNumber: 1,
                            newLineNumber: nil,
                            content: "removed"
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(diff.editorDecorations, [
            EditorDiffDecoration(lineNumber: 1, kind: .deleted)
        ])
    }

    private func initializeRepository(at rootURL: URL) throws {
        try runGit(["init", "-b", "main"], in: rootURL)
        try runGit(["config", "user.email", "test@example.com"], in: rootURL)
        try runGit(["config", "user.name", "Test"], in: rootURL)
    }

    private func makeRemoteBackedRuriBaseFixture() throws -> (
        parentURL: URL,
        rootURL: URL,
        seedURL: URL,
        worktreeURL: URL
    ) {
        let parentURL = try makeTemporaryDirectory()
        let projectURL = parentURL.appending(path: "Project", directoryHint: .isDirectory)
        let remoteURL = parentURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let seedURL = parentURL.appending(path: "seed", directoryHint: .isDirectory)
        let rootURL = projectURL.appending(path: "ruri-base", directoryHint: .isDirectory)
        let worktreeURL = projectURL.appending(path: "feature-one", directoryHint: .isDirectory)

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

        return (
            parentURL: parentURL,
            rootURL: rootURL,
            seedURL: seedURL,
            worktreeURL: worktreeURL
        )
    }

    private func pushRemoteOnlyCommit(from seedURL: URL) throws {
        try "remote\n".write(to: seedURL.appending(path: "RemoteOnly.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "RemoteOnly.txt"], in: seedURL)
        try runGit(["commit", "-m", "remote only"], in: seedURL)
        try runGit(["push"], in: seedURL)
    }

    private func pushRemoteBranch(named branchName: String, from seedURL: URL) throws {
        try runGit(["switch", "main"], in: seedURL)
        try runGit(["switch", "-c", branchName], in: seedURL)
        try "remote branch\n".write(
            to: seedURL.appending(path: "RemoteBranch.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "RemoteBranch.txt"], in: seedURL)
        try runGit(["commit", "-m", "remote branch"], in: seedURL)
        try runGit(["push", "-u", "origin", branchName], in: seedURL)
        try runGit(["switch", "main"], in: seedURL)
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
