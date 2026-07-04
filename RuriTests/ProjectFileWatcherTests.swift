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

    func testFileEventMarksOnlyDirtyFile() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let filePath = rootURL
            .appending(path: "Sources/App.kt")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedEventChanges(
            for: [
                ProjectFileWatcher.FileSystemEvent(
                    path: filePath,
                    flags: eventFlags(
                        kFSEventStreamEventFlagItemIsFile,
                        kFSEventStreamEventFlagItemModified
                    )
                )
            ],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.dirtyFilePaths, [filePath])
        XCTAssertEqual(changes.first?.dirtyDirectoryPaths, [])
        XCTAssertFalse(changes.first?.requiresWorkspaceRescan ?? true)
    }

    func testFileCreateMarksFileAndParentDirectoryDirty() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let filePath = rootURL
            .appending(path: "Sources/New.kt")
            .path(percentEncoded: false)
        let parentPath = rootURL
            .appending(path: "Sources")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedEventChanges(
            for: [
                ProjectFileWatcher.FileSystemEvent(
                    path: filePath,
                    flags: eventFlags(
                        kFSEventStreamEventFlagItemIsFile,
                        kFSEventStreamEventFlagItemCreated
                    )
                )
            ],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.dirtyFilePaths, [filePath])
        XCTAssertEqual(changes.first?.dirtyDirectoryPaths, [parentPath])
        XCTAssertEqual(changes.first?.dirtyRecursivePaths, [])
    }

    func testDirectoryCreateMarksParentAndRecursiveDirectoryDirty() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let directoryPath = rootURL
            .appending(path: "Sources/NewModule")
            .path(percentEncoded: false)
        let parentPath = rootURL
            .appending(path: "Sources")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedEventChanges(
            for: [
                ProjectFileWatcher.FileSystemEvent(
                    path: directoryPath,
                    flags: eventFlags(
                        kFSEventStreamEventFlagItemIsDir,
                        kFSEventStreamEventFlagItemCreated
                    )
                )
            ],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.dirtyRecursivePaths, [directoryPath])
        XCTAssertEqual(changes.first?.dirtyDirectoryPaths, [parentPath])
        XCTAssertFalse(changes.first?.requiresWorkspaceRescan ?? true)
    }

    func testDirectoryRenameMarksParentAndRecursiveDirectoryDirty() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let directoryPath = rootURL
            .appending(path: "Sources/Renamed")
            .path(percentEncoded: false)
        let parentPath = rootURL
            .appending(path: "Sources")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedEventChanges(
            for: [
                ProjectFileWatcher.FileSystemEvent(
                    path: directoryPath,
                    flags: eventFlags(
                        kFSEventStreamEventFlagItemIsDir,
                        kFSEventStreamEventFlagItemRenamed
                    )
                )
            ],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.dirtyRecursivePaths, [directoryPath])
        XCTAssertEqual(changes.first?.dirtyDirectoryPaths, [parentPath])
    }

    func testDroppedEventsRequestWorkspaceRescanAndFullGitRefresh() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let directoryPath = rootURL
            .appending(path: "Sources")
            .path(percentEncoded: false)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedEventChanges(
            for: [
                ProjectFileWatcher.FileSystemEvent(
                    path: directoryPath,
                    flags: eventFlags(
                        kFSEventStreamEventFlagMustScanSubDirs,
                        kFSEventStreamEventFlagUserDropped
                    )
                )
            ],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.dirtyRecursivePaths, [directoryPath])
        XCTAssertTrue(changes.first?.requiresWorkspaceRescan ?? false)
        XCTAssertTrue(changes.first?.requiresFullGitRefresh ?? false)
    }

    private func eventFlags(_ flags: Int...) -> FSEventStreamEventFlags {
        flags.reduce(FSEventStreamEventFlags(0)) { result, flag in
            result | FSEventStreamEventFlags(flag)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }
}
