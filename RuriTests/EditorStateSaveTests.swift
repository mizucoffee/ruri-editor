//
//  EditorStateSaveTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorStateSaveTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSaveSelectedFileWritesCurrentTextAndClearsDirtyState() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("changed")

        XCTAssertTrue(editor.canSave)

        await editor.saveSelectedFile()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "changed")
        XCTAssertFalse(editor.canSave)
    }

    func testSaveTabWritesCurrentText() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Tab.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)

        editor.updateText("tab change", in: tabID)

        XCTAssertTrue(editor.canSaveTab(tabID))

        await editor.saveTab(tabID)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "tab change")
        XCTAssertFalse(editor.canSaveTab(tabID))
    }

    func testEditingDoesNotWriteFileUntilManualSave() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Manual.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        editor.updateSelectedText("changed")
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
        XCTAssertEqual(editor.selectedText, "changed")
        XCTAssertTrue(editor.canSave)
    }

    func testRenameOpenFileUpdatesTabAndSaveTarget() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let renamedURL = rootURL.appending(path: "Renamed.txt").standardizedFileURL
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState()
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("changed")

        await editor.renameFileTreeNode(fileURL, to: "Renamed.txt")

        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)))
        XCTAssertEqual(editor.tabs.first?.url, renamedURL)
        XCTAssertTrue(editor.canSave)

        await editor.saveSelectedFile()

        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "changed")
        XCTAssertFalse(editor.canSave)
    }

    func testExternalUpdateReloadsCleanOpenFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(for: rootURL)

        XCTAssertEqual(editor.selectedText, "external content")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .externallyModified)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalUpdateDoesNotOverwriteDirtyOpenFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(for: rootURL)

        XCTAssertEqual(editor.selectedText, "local edit")
        XCTAssertEqual(editor.tabs.first?.lastSavedText, "external content")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .conflict)
        XCTAssertTrue(editor.canSave)
    }

    func testSavingConflictRequestsConfirmationBeforeOverwriting() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(for: rootURL)

        await editor.saveSelectedFile()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "external content")
        XCTAssertEqual(editor.saveConflictConfirmation?.fileName, "Note.txt")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .conflict)
        XCTAssertTrue(editor.canSave)
    }

    func testCancelingConflictSaveKeepsConflict() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(for: rootURL)
        await editor.saveSelectedFile()

        editor.cancelSaveConflict()

        XCTAssertNil(editor.saveConflictConfirmation)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "external content")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .conflict)
        XCTAssertTrue(editor.canSave)
    }

    func testConfirmingConflictSaveOverwritesExternalContent() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(for: rootURL)
        await editor.saveSelectedFile()

        await editor.confirmSaveConflictOverwrite()

        XCTAssertNil(editor.saveConflictConfirmation)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "local edit")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalUpdateWithSameSignatureUsesChangedPathContentComparison() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let fixedModificationDate = Date(timeIntervalSince1970: 1_000)
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try "external".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        await editor.handleExternalProjectChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(editor.selectedText, "external")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .externallyModified)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalUpdateWithSameSignatureWithoutChangedPathIsSkipped() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let fixedModificationDate = Date(timeIntervalSince1970: 1_000)
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try "external".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        await editor.handleExternalProjectChange(for: rootURL)

        XCTAssertEqual(editor.selectedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalDeletionKeepsOpenFileAndSaveRecreatesIt() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try fileManager.removeItem(at: fileURL)
        await editor.handleExternalProjectChange(for: rootURL)

        XCTAssertEqual(editor.selectedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .deleted)
        XCTAssertTrue(editor.canSave)

        await editor.saveSelectedFile()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalProjectChangeRefreshesRootTree() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstURL = rootURL.appending(path: "First.txt")
        let secondURL = rootURL.appending(path: "Second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)

        let editor = EditorState(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        XCTAssertEqual(editor.fileTree.map(\.name), ["First.txt"])

        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try fileManager.removeItem(at: firstURL)
        await editor.handleExternalProjectChange(for: rootURL)

        XCTAssertEqual(editor.fileTree.map(\.name), ["Second.txt"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

}
