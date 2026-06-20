//
//  EditorDocumentStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class EditorDocumentStoreTests: XCTestCase {
    func testUpdateTextMarksDocumentAsEditedAndUnsaved() {
        let url = URL(filePath: "/tmp/Note.txt")
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")

        store.updateText("changed", for: documentID)

        let snapshot = store.snapshot(for: EditorTab(documentID: documentID))
        XCTAssertEqual(snapshot?.text, "changed")
        XCTAssertTrue(snapshot?.hasUserEdited ?? false)
        XCTAssertTrue(snapshot?.hasUnsavedChanges ?? false)
    }

    func testMarkSavedUsesSavedTextWithoutDroppingLaterUnsavedChanges() {
        let url = URL(filePath: "/tmp/Note.txt")
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")
        let tab = EditorTab(documentID: documentID)

        store.updateText("first change", for: documentID)
        store.markSaved(documentID, savedText: "first change")
        store.updateText("second change", for: documentID)

        let snapshot = store.snapshot(for: tab)
        XCTAssertEqual(snapshot?.lastSavedText, "first change")
        XCTAssertEqual(snapshot?.text, "second change")
        XCTAssertTrue(snapshot?.hasUnsavedChanges ?? false)
    }

    func testOpenDocumentCreatesStableSessionUntilDocumentCloses() {
        let url = URL(filePath: "/tmp/Note.txt")
        var store = EditorDocumentStore()

        let documentID = store.openDocument(url: url, text: "original")
        let firstSession = store.session(for: documentID)
        let secondSession = store.session(for: documentID)

        XCTAssertNotNil(firstSession)
        XCTAssertTrue(firstSession === secondSession)

        store.closeDocument(documentID)

        XCTAssertNil(store.session(for: documentID))
    }

    func testUpdateSelectionAndScrollOriginStoresEditorState() throws {
        let url = URL(filePath: "/tmp/Note.txt")
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")

        store.updateSelection(NSRange(location: 2, length: 3), for: documentID)
        store.updateScrollOrigin(CGPoint(x: 0, y: 48), for: documentID)

        let session = try XCTUnwrap(store.session(for: documentID))
        XCTAssertTrue(NSEqualRanges(session.selectedRange, NSRange(location: 2, length: 3)))
        XCTAssertEqual(session.scrollOrigin, CGPoint(x: 0, y: 48))
    }

    func testExternalSnapshotReloadsCleanDocument() {
        let url = URL(filePath: "/tmp/Note.txt")
        let signature = ProjectFileSignature(
            modificationDate: Date(timeIntervalSince1970: 1),
            fileSize: 8
        )
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")

        store.applyExternalFileSnapshot(
            ProjectFileSnapshot(text: "external", signature: signature),
            to: documentID
        )

        let snapshot = store.snapshot(for: EditorTab(documentID: documentID))
        XCTAssertEqual(snapshot?.text, "external")
        XCTAssertEqual(snapshot?.lastSavedText, "external")
        XCTAssertEqual(snapshot?.lastKnownFileSignature, signature)
        XCTAssertEqual(snapshot?.externalStatus, .externallyModified)
        XCTAssertFalse(snapshot?.hasUnsavedChanges ?? true)
    }

    func testExternalSnapshotPreservesDirtyDocumentAndMarksConflict() {
        let url = URL(filePath: "/tmp/Note.txt")
        let signature = ProjectFileSignature(
            modificationDate: Date(timeIntervalSince1970: 2),
            fileSize: 8
        )
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")

        store.updateText("local edit", for: documentID)
        store.applyExternalFileSnapshot(
            ProjectFileSnapshot(text: "external", signature: signature),
            to: documentID
        )

        let snapshot = store.snapshot(for: EditorTab(documentID: documentID))
        XCTAssertEqual(snapshot?.text, "local edit")
        XCTAssertEqual(snapshot?.lastSavedText, "external")
        XCTAssertEqual(snapshot?.lastKnownFileSignature, signature)
        XCTAssertEqual(snapshot?.externalStatus, .conflict)
        XCTAssertTrue(snapshot?.hasUnsavedChanges ?? false)
    }

    func testExternalDeletionKeepsDocumentSaveable() {
        let url = URL(filePath: "/tmp/Note.txt")
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")

        store.markExternalFileDeleted(documentID)

        let snapshot = store.snapshot(for: EditorTab(documentID: documentID))
        XCTAssertEqual(snapshot?.text, "original")
        XCTAssertEqual(snapshot?.externalStatus, .deleted)
        XCTAssertTrue(snapshot?.canSave ?? false)
    }

    func testMarkSavedClearsExternalStatusAndUpdatesSignature() {
        let url = URL(filePath: "/tmp/Note.txt")
        let signature = ProjectFileSignature(
            modificationDate: Date(timeIntervalSince1970: 3),
            fileSize: 8
        )
        var store = EditorDocumentStore()
        let documentID = store.openDocument(url: url, text: "original")

        store.markExternalFileDeleted(documentID)
        store.markSaved(documentID, savedText: "original", signature: signature)

        let snapshot = store.snapshot(for: EditorTab(documentID: documentID))
        XCTAssertEqual(snapshot?.lastSavedText, "original")
        XCTAssertEqual(snapshot?.lastKnownFileSignature, signature)
        XCTAssertEqual(snapshot?.externalStatus, .normal)
        XCTAssertFalse(snapshot?.canSave ?? true)
    }

}
