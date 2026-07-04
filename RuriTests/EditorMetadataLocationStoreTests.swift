//
//  EditorMetadataLocationStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorMetadataLocationStoreTests: XCTestCase {
    private let worktreeRootURL = URL(filePath: "/tmp/Container/feature-branch")
    private let baseWorkspaceURL = URL(filePath: "/tmp/Container/ruri-base")

    // MARK: - metadataDirectoryURL

    func testMetadataDirectoryURLForRuriStyleWorktreeUsesParentDirectory() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(worktreeRootURL: worktreeRootURL, isRuriStyleWorktree: true)

        let url = store.metadataDirectoryURL(snapshot: snapshot, baseWorkspaceURL: nil)

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/.ruri/").standardizedFileURL)
    }

    func testMetadataDirectoryURLWithBaseWorkspaceUsesBaseParentDirectory() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(worktreeRootURL: worktreeRootURL)

        let url = store.metadataDirectoryURL(snapshot: snapshot, baseWorkspaceURL: baseWorkspaceURL)

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/.ruri/").standardizedFileURL)
    }

    func testMetadataDirectoryURLWithoutBaseWorkspaceUsesWorktreeRoot() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(worktreeRootURL: worktreeRootURL)

        let url = store.metadataDirectoryURL(snapshot: snapshot, baseWorkspaceURL: nil)

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/feature-branch/.ruri/").standardizedFileURL)
    }

    func testMetadataDirectoryURLPrefersRuriStyleWorktreeOverBaseWorkspace() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(
            worktreeRootURL: URL(filePath: "/tmp/Other/worktree"),
            isRuriStyleWorktree: true
        )

        let url = store.metadataDirectoryURL(snapshot: snapshot, baseWorkspaceURL: baseWorkspaceURL)

        XCTAssertEqual(url, URL(filePath: "/tmp/Other/.ruri/").standardizedFileURL)
    }

    // MARK: - fallbackMetadataDirectoryURL

    func testFallbackMetadataDirectoryURLForRuriBaseUsesParentDirectory() {
        var store = EditorMetadataLocationStore()
        store.fileExists = { _ in
            XCTFail("ruri-base workspace should not require a sibling check")
            return false
        }

        let url = store.fallbackMetadataDirectoryURL(for: baseWorkspaceURL)

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/.ruri/").standardizedFileURL)
    }

    func testFallbackMetadataDirectoryURLWithExistingSiblingBaseUsesParentDirectory() {
        var store = EditorMetadataLocationStore()
        var checkedURLs: [URL] = []
        store.fileExists = { url in
            checkedURLs.append(url)
            return true
        }

        let url = store.fallbackMetadataDirectoryURL(for: worktreeRootURL)

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/.ruri/").standardizedFileURL)
        XCTAssertEqual(checkedURLs.count, 1)
        XCTAssertEqual(
            checkedURLs.first.map(FileURLRewriter.normalizedPath),
            FileURLRewriter.normalizedPath(baseWorkspaceURL)
        )
    }

    func testFallbackMetadataDirectoryURLWithoutSiblingBaseUsesWorkspaceRoot() {
        var store = EditorMetadataLocationStore()
        store.fileExists = { _ in false }

        let url = store.fallbackMetadataDirectoryURL(for: worktreeRootURL)

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/feature-branch/.ruri/").standardizedFileURL)
    }

    func testFallbackMetadataDirectoryURLStandardizesTrailingSlash() {
        var store = EditorMetadataLocationStore()
        store.fileExists = { _ in false }

        let url = store.fallbackMetadataDirectoryURL(
            for: URL(filePath: "/tmp/Container/feature-branch/", directoryHint: .isDirectory)
        )

        XCTAssertEqual(url, URL(filePath: "/tmp/Container/feature-branch/.ruri/").standardizedFileURL)
    }

    // MARK: - metadataRepositoryRootURL

    func testMetadataRepositoryRootURLForRuriStyleWorktreeIsNil() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(worktreeRootURL: worktreeRootURL, isRuriStyleWorktree: true)

        XCTAssertNil(store.metadataRepositoryRootURL(snapshot: snapshot, hasBaseWorkspace: false))
    }

    func testMetadataRepositoryRootURLWithBaseWorkspaceIsNil() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(worktreeRootURL: worktreeRootURL)

        XCTAssertNil(store.metadataRepositoryRootURL(snapshot: snapshot, hasBaseWorkspace: true))
    }

    func testMetadataRepositoryRootURLWithoutBaseWorkspaceIsWorktreeRoot() {
        let store = EditorMetadataLocationStore()
        let snapshot = makeSnapshot(worktreeRootURL: worktreeRootURL)

        XCTAssertEqual(
            store.metadataRepositoryRootURL(snapshot: snapshot, hasBaseWorkspace: false),
            worktreeRootURL.standardizedFileURL
        )
    }

    // MARK: - Helpers

    private func makeSnapshot(
        worktreeRootURL: URL,
        isRuriStyleWorktree: Bool = false
    ) -> GitRepositorySnapshot {
        GitRepositorySnapshot(
            repositoryRootURL: worktreeRootURL,
            worktreeRootURL: worktreeRootURL,
            openedRootURL: worktreeRootURL,
            gitDirectoryURL: worktreeRootURL.appending(path: ".git", directoryHint: .isDirectory),
            gitCommonDirectoryURL: worktreeRootURL.appending(path: ".git", directoryHint: .isDirectory),
            worktreeKind: .main,
            worktreeRootURLs: [worktreeRootURL],
            isRuriStyleWorktree: isRuriStyleWorktree,
            branch: .branch("main"),
            changesByURL: [:],
            diffsByURL: [:]
        )
    }
}
