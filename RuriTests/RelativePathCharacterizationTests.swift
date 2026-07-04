//
//  RelativePathCharacterizationTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

// Characterization tests for relative-path semantics (AGENT_EXPERIENCE.md H3).
// FileURLRewriter.relativePath(from:to:) is the single implementation: it
// normalizes both sides, returns "" when the paths are equal and nil when the
// target is not a descendant. Display fallbacks ("." for the tree copy action,
// lastPathComponent for search/usage results) live at the call sites and are
// pinned per call site below.
final class RelativePathCharacterizationTests: XCTestCase {
    private let fileManager = FileManager.default

    // MARK: - FileURLRewriter.relativePath (canonical: equal -> "", non-descendant -> nil)

    func testRelativePathForDescendants() {
        let root = URL(filePath: "/tmp/root")

        XCTAssertEqual(
            FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/root/a.swift")),
            "a.swift"
        )
        XCTAssertEqual(
            FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/root/a/b.swift")),
            "a/b.swift"
        )
        XCTAssertEqual(
            FileURLRewriter.relativePath(from: URL(filePath: "/tmp/root/"), to: URL(filePath: "/tmp/root/a.swift")),
            "a.swift"
        )
        XCTAssertEqual(
            FileURLRewriter.relativePath(from: URL(filePath: "/"), to: URL(filePath: "/a")),
            "a"
        )
    }

    func testRelativePathNormalizesTrailingSlashOfDirectoryTargets() {
        let root = URL(filePath: "/tmp/root")

        XCTAssertEqual(
            FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/root/a/")),
            "a"
        )
    }

    func testRelativePathReturnsEmptyStringForEqualPaths() {
        let root = URL(filePath: "/tmp/root")

        XCTAssertEqual(FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/root")), "")
        XCTAssertEqual(FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/root/")), "")
    }

    func testRelativePathReturnsNilForNonDescendants() {
        let root = URL(filePath: "/tmp/root")

        XCTAssertNil(FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/other/a.swift")))
        XCTAssertNil(FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp/root2/a.swift")))
        XCTAssertNil(FileURLRewriter.relativePath(from: root, to: URL(filePath: "/tmp")))
    }

    func testIsDescendantOrSameFollowsRelativePath() {
        let root = URL(filePath: "/tmp/root")

        XCTAssertTrue(FileURLRewriter.isDescendantOrSame(URL(filePath: "/tmp/root"), of: root))
        XCTAssertTrue(FileURLRewriter.isDescendantOrSame(URL(filePath: "/tmp/root/a"), of: root))
        XCTAssertFalse(FileURLRewriter.isDescendantOrSame(URL(filePath: "/tmp/root2"), of: root))
        XCTAssertFalse(FileURLRewriter.isDescendantOrSame(URL(filePath: "/tmp"), of: root))
    }

    // MARK: - CodeUsageResult call site (display fallback to lastPathComponent)

    private func usageRelativePath(projectPath: String, targetPath: String) -> String {
        CodeUsageResult.result(
            url: URL(filePath: targetPath),
            range: TextRange(location: 0, length: 1),
            text: "needle",
            projectURL: URL(filePath: projectPath)
        ).relativePath
    }

    func testUsageRelativePathBoundaries() {
        XCTAssertEqual(usageRelativePath(projectPath: "/tmp/root", targetPath: "/tmp/root/a.swift"), "a.swift")
        XCTAssertEqual(usageRelativePath(projectPath: "/tmp/root", targetPath: "/tmp/root/a/b.swift"), "a/b.swift")
        XCTAssertEqual(usageRelativePath(projectPath: "/tmp/root", targetPath: "/tmp/root"), "")
        XCTAssertEqual(usageRelativePath(projectPath: "/tmp/root", targetPath: "/tmp/root/a/"), "a")
        XCTAssertEqual(usageRelativePath(projectPath: "/tmp/root", targetPath: "/tmp/other/a.swift"), "a.swift")
        XCTAssertEqual(usageRelativePath(projectPath: "/tmp/root", targetPath: "/tmp/root2/a.swift"), "a.swift")
    }

    // MARK: - FileTreePathFormatter call site ("" -> ".", non-descendant -> nil)

    func testTreeRelativePathBoundaries() {
        let project = URL(filePath: "/tmp/root")

        XCTAssertEqual(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/root/a.swift"), projectURL: project), "a.swift")
        XCTAssertEqual(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/root"), projectURL: project), ".")
        XCTAssertEqual(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/root/"), projectURL: project), ".")
        XCTAssertEqual(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/root/a/"), projectURL: project), "a")
        XCTAssertNil(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/other/a.swift"), projectURL: project))
        XCTAssertNil(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/root2/a.swift"), projectURL: project))
        XCTAssertNil(FileTreePathFormatter.relativePath(for: URL(filePath: "/tmp/root/a.swift"), projectURL: nil))
    }

    // MARK: - GitService call site (root itself and outside files -> nil snapshot)

    func testGitServiceFileSnapshotBoundaries() async throws {
        _ = try TestSupport.gitExecutableURL(fileManager: fileManager)

        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }
        try TestSupport.initializeRepository(at: rootURL)

        let fileURL = rootURL.appending(path: "Tracked.txt")
        try "one\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try TestSupport.runGit(["add", "Tracked.txt"], in: rootURL)
        try TestSupport.runGit(["commit", "-m", "initial"], in: rootURL)

        let insideSnapshot = await GitService().fileSnapshot(for: fileURL, openedRootURL: rootURL)
        XCTAssertNotNil(insideSnapshot)

        let rootSnapshot = await GitService().fileSnapshot(for: rootURL, openedRootURL: rootURL)
        XCTAssertNil(rootSnapshot)

        let outsideURL = fileManager.temporaryDirectory.appending(path: "ruri-outside-\(UUID().uuidString).txt")
        try "outside\n".write(to: outsideURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: outsideURL) }

        let outsideSnapshot = await GitService().fileSnapshot(for: outsideURL, openedRootURL: rootURL)
        XCTAssertNil(outsideSnapshot)
    }

    // MARK: - GitIgnoreMatcher call site (non-descendant / root -> never ignored)

    func testGitIgnoreMatcherIgnoresOnlyDescendants() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }
        try "*\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertTrue(matcher.isIgnored(rootURL.appending(path: "a.txt"), isDirectory: false))
        XCTAssertFalse(matcher.isIgnored(rootURL, isDirectory: true))
        XCTAssertFalse(matcher.isIgnored(URL(filePath: "/tmp/elsewhere/a.txt"), isDirectory: false))
    }

    // MARK: - GitReviewDiffUpdate (git-reported relative strings; separate domain, kept as-is)

    func testReviewDiffUpdateTrimsSlashesInRequestedRelativePaths() {
        let update = GitReviewDiffUpdate(
            base: .uncommitted,
            targetBranch: .branch("main"),
            targetWorktreeRootURL: URL(filePath: "/tmp/root"),
            baseRevision: "HEAD",
            requestedRelativePaths: ["/a/b/", "c//", "plain"],
            files: []
        )

        XCTAssertEqual(update.requestedRelativePaths, ["a/b", "c", "plain"])

        let matchingFile = GitReviewFileDiff(
            oldRelativePath: nil,
            newRelativePath: "a/b",
            status: .added,
            additions: 0,
            deletions: 0,
            diff: SourceFileDiff(oldRelativePath: nil, newRelativePath: "a/b", hunks: [])
        )
        let otherFile = GitReviewFileDiff(
            oldRelativePath: nil,
            newRelativePath: "a/b/c",
            status: .added,
            additions: 0,
            deletions: 0,
            diff: SourceFileDiff(oldRelativePath: nil, newRelativePath: "a/b/c", hunks: [])
        )

        XCTAssertTrue(update.replaces(matchingFile))
        XCTAssertFalse(update.replaces(otherFile))
    }
}
