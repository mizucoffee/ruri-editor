//
//  EditorViewModelSaveTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorViewModelSaveTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSaveSelectedFileWritesCurrentTextAndClearsDirtyState() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel()
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

        let editor = EditorViewModel()
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
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

        let editor = EditorViewModel()
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(editor.selectedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)

        editor.focusEditor(tabID: tabID)

        XCTAssertEqual(editor.selectedText, "external content")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .externallyModified)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalFileOnlyUpdateKeepsFileTreeLoaded() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let otherURL = rootURL.appending(path: "Other.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other".write(to: otherURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)

        XCTAssertEqual(editor.fileTree.map(\.name), ["Note.txt", "Other.txt"])

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(editor.fileTree.map(\.name), ["Note.txt", "Other.txt"])

        editor.focusEditor(tabID: tabID)

        XCTAssertEqual(editor.selectedText, "external content")
        XCTAssertEqual(editor.fileTree.map(\.name), ["Note.txt", "Other.txt"])
    }

    func testExternalDirectoryUpdateKeepsRootTreeLoaded() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourcesURL = rootURL.appending(path: "Sources", directoryHint: .isDirectory)
        let docsURL = rootURL.appending(path: "Docs", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "app".write(to: sourcesURL.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "readme".write(to: docsURL.appending(path: "Readme.md"), atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        XCTAssertEqual(editor.fileTree.map(\.name), ["Docs", "Sources"])

        try "feature".write(to: sourcesURL.appending(path: "Feature.swift"), atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(ProjectFileWatcher.Change.directoryChange(
            rootURL: rootURL,
            paths: [sourcesURL.path(percentEncoded: false)]
        ))

        XCTAssertEqual(editor.fileTree.map(\.name), ["Docs", "Sources"])
    }

    func testExternalUpdatesMaterializeSelectedDocumentOnlyOnFocus() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstURL = rootURL.appending(path: "First.txt")
        let secondURL = rootURL.appending(path: "Second.txt")
        try "first original".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second original".write(to: secondURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(firstURL)
        let firstTabID = try XCTUnwrap(editor.selectedTabID)
        await editor.openFilePreservingSelectedTab(secondURL)
        let secondTabID = try XCTUnwrap(editor.selectedTabID)

        try "first external".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second external".write(to: secondURL, atomically: true, encoding: .utf8)
        await editor.handleExternalProjectChange(ProjectFileWatcher.Change.fileChange(
            rootURL: rootURL,
            paths: [
                firstURL.standardizedFileURL.path(percentEncoded: false),
                secondURL.standardizedFileURL.path(percentEncoded: false)
            ]
        ))

        XCTAssertEqual(editor.tab(for: firstTabID)?.text, "first original")
        XCTAssertEqual(editor.tab(for: secondTabID)?.text, "second original")

        editor.focusEditor(tabID: secondTabID)

        XCTAssertEqual(editor.tab(for: firstTabID)?.text, "first original")
        XCTAssertEqual(editor.tab(for: secondTabID)?.text, "second external")

        editor.selectTab(firstTabID)
        editor.focusEditor(tabID: firstTabID)

        XCTAssertEqual(editor.tab(for: firstTabID)?.text, "first external")
    }

    func testExternalUpdateDoesNotOverwriteDirtyOpenFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        let tabID = try XCTUnwrap(editor.selectedTabID)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(editor.selectedText, "local edit")
        XCTAssertEqual(editor.tabs.first?.lastSavedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)

        editor.focusEditor(tabID: tabID)

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )
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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )
        await editor.saveSelectedFile()

        await editor.confirmSaveConflictOverwrite()

        XCTAssertNil(editor.saveConflictConfirmation)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "local edit")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)
    }

    func testSavingDetectsExternalChangeNotYetObservedByWatcher() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        // watcherに通知しないまま外部変更を加え、保存時のcompare-and-swapだけで検出させる。
        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)

        await editor.saveSelectedFile()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "external content")
        XCTAssertEqual(editor.saveConflictConfirmation?.fileName, "Note.txt")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .conflict)
        XCTAssertTrue(editor.canSave)

        await editor.confirmSaveConflictOverwrite()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "local edit")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)
    }

    func testConfirmedOverwriteRepromptsWhenFileChangedAgain() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)
        editor.updateSelectedText("local edit")

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )
        await editor.saveSelectedFile()

        XCTAssertEqual(editor.saveConflictConfirmation?.fileName, "Note.txt")

        // 確認ダイアログ表示中にさらに外部変更が入った場合は上書きせず再確認する。
        try "external content again".write(to: fileURL, atomically: true, encoding: .utf8)

        await editor.confirmSaveConflictOverwrite()

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "external content again")
        XCTAssertEqual(editor.saveConflictConfirmation?.fileName, "Note.txt")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .conflict)
        XCTAssertTrue(editor.canSave)

        await editor.confirmSaveConflictOverwrite()

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try "external".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(editor.selectedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)

        editor.focusEditor(tabID: try XCTUnwrap(editor.selectedTabID))

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try "external".write(to: fileURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        await editor.handleExternalContentChange(for: rootURL)

        XCTAssertEqual(editor.selectedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)
    }

    func testExternalDeletionKeepsOpenFileAndSaveRecreatesIt() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)
        await editor.openFile(fileURL)

        try fileManager.removeItem(at: fileURL)
        await editor.handleExternalContentChange(
            for: rootURL,
            changedPaths: [fileURL.standardizedFileURL.path(percentEncoded: false)]
        )

        XCTAssertEqual(editor.selectedText, "original")
        XCTAssertEqual(editor.tabs.first?.externalStatus, .normal)
        XCTAssertFalse(editor.canSave)

        editor.focusEditor(tabID: try XCTUnwrap(editor.selectedTabID))

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

        let editor = EditorViewModel(isFileWatchingEnabled: false)
        await editor.openProject(rootURL)

        XCTAssertEqual(editor.fileTree.map(\.name), ["First.txt"])

        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try fileManager.removeItem(at: firstURL)
        await editor.handleExternalContentChange(for: rootURL)

        XCTAssertEqual(editor.fileTree.map(\.name), ["Second.txt"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }

}
