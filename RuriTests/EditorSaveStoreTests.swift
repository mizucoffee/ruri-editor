//
//  EditorSaveStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorSaveStoreTests: XCTestCase {
    private let workspaceID = URL(filePath: "/tmp/Project")
    private let fileURL = URL(filePath: "/tmp/Project/Note.txt")

    func testBeginSaveWithoutDocumentSkips() {
        var store = EditorSaveStore()

        let action = store.beginSave(
            document: nil,
            tabID: UUID(),
            workspaceID: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: true
        )

        XCTAssertEqual(action, .skip)
        XCTAssertNil(store.pendingConflictConfirmation)
    }

    func testBeginSaveWithNormalDocumentWritesCurrentText() {
        var store = EditorSaveStore()
        let document = OpenDocument(
            url: fileURL,
            text: "local edit",
            lastSavedText: "original"
        )

        let action = store.beginSave(
            document: document,
            tabID: UUID(),
            workspaceID: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: true
        )

        XCTAssertEqual(action, .write(textToSave: "local edit"))
        XCTAssertNil(store.pendingConflictConfirmation)
    }

    func testBeginSaveWithConflictRecordsConfirmation() {
        var store = EditorSaveStore()
        let tabID = UUID()
        let document = OpenDocument(
            url: fileURL,
            text: "local edit",
            lastSavedText: "original",
            externalStatus: .conflict
        )

        let action = store.beginSave(
            document: document,
            tabID: tabID,
            workspaceID: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: true
        )

        XCTAssertEqual(action, .conflict(recordedConfirmation: true))
        XCTAssertEqual(store.pendingConflictConfirmation?.workspaceID, workspaceID)
        XCTAssertEqual(store.pendingConflictConfirmation?.tabID, tabID)
        XCTAssertEqual(store.pendingConflictConfirmation?.url, fileURL)
        XCTAssertEqual(store.pendingConflictConfirmation?.fileName, "Note.txt")
    }

    func testBeginSaveWithConflictWithoutPresentingDoesNotRecordConfirmation() {
        var store = EditorSaveStore()
        let document = OpenDocument(
            url: fileURL,
            text: "local edit",
            lastSavedText: "original",
            externalStatus: .conflict
        )

        let action = store.beginSave(
            document: document,
            tabID: UUID(),
            workspaceID: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: false
        )

        XCTAssertEqual(action, .conflict(recordedConfirmation: false))
        XCTAssertNil(store.pendingConflictConfirmation)
    }

    func testBeginSaveWithConflictAllowingOverwriteWrites() {
        var store = EditorSaveStore()
        let document = OpenDocument(
            url: fileURL,
            text: "local edit",
            lastSavedText: "original",
            externalStatus: .conflict
        )

        let action = store.beginSave(
            document: document,
            tabID: UUID(),
            workspaceID: workspaceID,
            allowingConflictOverwrite: true,
            presentsConflictConfirmation: true
        )

        XCTAssertEqual(action, .write(textToSave: "local edit"))
        XCTAssertNil(store.pendingConflictConfirmation)
    }

    func testTakeConfirmationForOverwriteReturnsAndClearsConfirmation() {
        var store = EditorSaveStore()
        let tabID = UUID()
        let document = OpenDocument(
            url: fileURL,
            text: "local edit",
            lastSavedText: "original",
            externalStatus: .conflict
        )
        _ = store.beginSave(
            document: document,
            tabID: tabID,
            workspaceID: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: true
        )

        let confirmation = store.takeConfirmationForOverwrite()

        XCTAssertEqual(confirmation?.tabID, tabID)
        XCTAssertNil(store.pendingConflictConfirmation)
        XCTAssertNil(store.takeConfirmationForOverwrite())
    }

    func testCancelConflictClearsConfirmation() {
        var store = EditorSaveStore()
        let document = OpenDocument(
            url: fileURL,
            text: "local edit",
            lastSavedText: "original",
            externalStatus: .conflict
        )
        _ = store.beginSave(
            document: document,
            tabID: UUID(),
            workspaceID: workspaceID,
            allowingConflictOverwrite: false,
            presentsConflictConfirmation: true
        )

        store.cancelConflict()

        XCTAssertNil(store.pendingConflictConfirmation)
    }
}
