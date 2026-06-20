//
//  ProjectFileWatcherTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class ProjectFileWatcherTests: XCTestCase {
    private let fileManager = FileManager.default

    func testClassifiesGitMetadataSeparatelyFromContentChanges() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let contentPath = rootURL
            .appending(path: "Sources/App.kt")
            .path(percentEncoded: false)
        let gitMetadataPath = rootURL
            .appending(path: ".git/index")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: [contentPath, gitMetadataPath],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.rootURL, rootURL.standardizedFileURL)
        XCTAssertEqual(changes.first?.changedPaths, [contentPath])
        XCTAssertEqual(changes.first?.gitMetadataChangedPaths, [gitMetadataPath])
    }

    func testIgnoresRuriMetadataChanges() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let ruriMetadataPath = rootURL
            .appending(path: ".ruri/worktree-metadata.json")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: [ruriMetadataPath],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes, [])
    }

    func testClassifiesEmptyEventPathsAsNoChanges() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let watcher = ProjectFileWatcher { _ in }

        XCTAssertEqual(
            watcher.classifiedChanges(for: [], rootURLs: [rootURL]),
            []
        )
    }

    func testNestedRootsPreferMostSpecificRoot() throws {
        let rootURL = try makeTemporaryDirectory()
        let nestedRootURL = rootURL.appending(path: "nested", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: rootURL) }
        try fileManager.createDirectory(at: nestedRootURL, withIntermediateDirectories: true)

        let contentPath = nestedRootURL
            .appending(path: "Sources/App.kt")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: [contentPath],
            rootURLs: [rootURL, nestedRootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.rootURL, nestedRootURL.standardizedFileURL)
        XCTAssertEqual(changes.first?.changedPaths, [contentPath])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
