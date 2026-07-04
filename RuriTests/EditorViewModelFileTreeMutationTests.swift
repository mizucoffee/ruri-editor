//
//  EditorViewModelFileTreeMutationTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorViewModelFileTreeMutationTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCreateFileTreeNodeCreatesFileSelectsItAndOpensTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        let closedDocument = await editor.createFileTreeNode(
            named: "New.txt",
            in: rootURL,
            isDirectory: false
        )

        let newURL = rootURL.appending(path: "New.txt").standardizedFileURL
        XCTAssertNil(closedDocument)
        XCTAssertTrue(fileManager.fileExists(atPath: newURL.path(percentEncoded: false)))
        XCTAssertTrue(editor.fileTree.contains { $0.name == "New.txt" })
        let selectedURL = try XCTUnwrap(editor.selectedFileTreeURL)
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedURL, newURL))
        XCTAssertEqual(editor.mainTabs.count, 1)
        let tabURL = try XCTUnwrap(editor.mainTabs.first?.url)
        XCTAssertTrue(FileURLRewriter.urlsMatch(tabURL, newURL))
    }

    func testCreateFileTreeNodeCreatesFolderWithoutOpeningTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        await editor.createFileTreeNode(named: "Sources", in: rootURL, isDirectory: true)

        let newNode = editor.fileTree.first { $0.name == "Sources" }
        XCTAssertTrue(try XCTUnwrap(newNode).isDirectory)
        XCTAssertEqual(editor.selectedFileTreeURL, newNode?.url)
        XCTAssertTrue(editor.mainTabs.isEmpty)
    }

    func testCreateFileTreeNodePresentsErrorWhenDestinationExists() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "existing".write(to: rootURL.appending(path: "New.txt"), atomically: true, encoding: .utf8)
        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        await editor.createFileTreeNode(named: "New.txt", in: rootURL, isDirectory: false)

        XCTAssertNotNil(editor.currentError)
        XCTAssertTrue(editor.mainTabs.isEmpty)
    }

    func testDeleteFileTreeNodeTrashesFileAndClosesOpenTab() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt").standardizedFileURL
        try "contents".write(to: fileURL, atomically: true, encoding: .utf8)
        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        XCTAssertEqual(editor.mainTabs.count, 1)

        let closedDocuments = await editor.deleteFileTreeNode(fileURL)

        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)))
        XCTAssertEqual(closedDocuments.map(\.documentID), [fileURL])
        XCTAssertTrue(editor.mainTabs.isEmpty)
        XCTAssertFalse(editor.fileTree.contains { $0.name == "Note.txt" })
    }

    func testDeleteFileTreeNodeClosesTabsUnderDeletedFolder() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let folderURL = rootURL.appending(path: "Sources")
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
        let firstURL = folderURL.appending(path: "App.swift").standardizedFileURL
        let secondURL = folderURL.appending(path: "Model.swift").standardizedFileURL
        try "app".write(to: firstURL, atomically: true, encoding: .utf8)
        try "model".write(to: secondURL, atomically: true, encoding: .utf8)
        let keptURL = rootURL.appending(path: "Keep.txt").standardizedFileURL
        try "keep".write(to: keptURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(firstURL)
        await editor.openFilePreservingSelectedTab(secondURL)
        await editor.openFilePreservingSelectedTab(keptURL)
        XCTAssertEqual(editor.mainTabs.count, 3)

        let closedDocuments = await editor.deleteFileTreeNode(
            folderURL.standardizedFileURL
        )

        XCTAssertEqual(Set(closedDocuments.map(\.documentID)), Set([firstURL, secondURL]))
        XCTAssertEqual(editor.mainTabs.map(\.url), [keptURL])
        XCTAssertFalse(editor.fileTree.contains { $0.name == "Sources" })
        XCTAssertFalse(fileManager.fileExists(atPath: folderURL.path(percentEncoded: false)))
    }

    func testDuplicateFileTreeNodeCreatesCopyAndSelectsIt() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "contents".write(to: fileURL, atomically: true, encoding: .utf8)
        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        await editor.duplicateFileTreeNode(fileURL.standardizedFileURL)

        let copyURL = rootURL.appending(path: "Note copy.txt").standardizedFileURL
        XCTAssertEqual(try String(contentsOf: copyURL, encoding: .utf8), "contents")
        XCTAssertTrue(editor.fileTree.contains { $0.name == "Note copy.txt" })
        let selectedURL = try XCTUnwrap(editor.selectedFileTreeURL)
        XCTAssertTrue(FileURLRewriter.urlsMatch(selectedURL, copyURL))
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }
}
