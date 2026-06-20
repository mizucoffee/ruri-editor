//
//  EditorDocumentStore.swift
//  ruri
//

import Foundation

struct EditorDocumentStore {
    private var documentsByID: [OpenDocument.ID: OpenDocument] = [:]
    private var sessionsByID: [OpenDocument.ID: EditorDocumentSession] = [:]

    mutating func reset() {
        documentsByID = [:]
        sessionsByID = [:]
    }

    func document(for id: OpenDocument.ID) -> OpenDocument? {
        documentsByID[id]
    }

    func session(for id: OpenDocument.ID) -> EditorDocumentSession? {
        sessionsByID[id]
    }

    var documents: [OpenDocument] {
        documentsByID.values.sorted {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }
    }

    mutating func openDocument(
        url: URL,
        text: String,
        signature: ProjectFileSignature? = nil
    ) -> OpenDocument.ID {
        let document = OpenDocument(
            url: url,
            text: text,
            lastSavedText: text,
            lastKnownFileSignature: signature
        )
        documentsByID[document.id] = document
        sessionsByID[document.id] = EditorDocumentSession()
        return document.id
    }

    mutating func closeDocument(_ id: OpenDocument.ID) {
        documentsByID[id] = nil
        sessionsByID[id] = nil
    }

    mutating func updateText(_ newText: String, for id: OpenDocument.ID) {
        guard var document = documentsByID[id],
              document.text != newText else {
            return
        }

        document.text = newText
        document.hasUserEdited = true
        if document.externalStatus == .externallyModified {
            document.externalStatus = .normal
        }
        documentsByID[id] = document
    }

    mutating func markUserEdited(_ id: OpenDocument.ID) {
        guard var document = documentsByID[id],
              !document.hasUserEdited else {
            return
        }

        document.hasUserEdited = true
        documentsByID[id] = document
    }

    mutating func markSaved(
        _ id: OpenDocument.ID,
        savedText: String,
        signature: ProjectFileSignature? = nil
    ) {
        guard var document = documentsByID[id] else { return }
        document.lastSavedText = savedText
        document.lastKnownFileSignature = signature
        document.externalStatus = .normal
        documentsByID[id] = document
    }

    mutating func applyExternalFileSnapshot(
        _ snapshot: ProjectFileSnapshot,
        to id: OpenDocument.ID
    ) {
        guard var document = documentsByID[id] else { return }

        if document.hasUnsavedChanges {
            document.lastSavedText = snapshot.text
            document.lastKnownFileSignature = snapshot.signature
            document.externalStatus = document.text == snapshot.text ? .externallyModified : .conflict
        } else {
            document.text = snapshot.text
            document.lastSavedText = snapshot.text
            document.lastKnownFileSignature = snapshot.signature
            document.externalStatus = .externallyModified
        }

        documentsByID[id] = document
    }

    mutating func markExternalFileDeleted(_ id: OpenDocument.ID) {
        guard var document = documentsByID[id] else { return }

        document.lastKnownFileSignature = nil
        document.externalStatus = .deleted
        documentsByID[id] = document
    }

    mutating func markExternalFileUnreadable(_ id: OpenDocument.ID, signature: ProjectFileSignature?) {
        guard var document = documentsByID[id] else { return }

        document.lastKnownFileSignature = signature
        document.externalStatus = .conflict
        documentsByID[id] = document
    }

    mutating func rewriteDocumentURLs(
        replacing oldURL: URL,
        with newURL: URL
    ) -> [OpenDocument.ID: OpenDocument.ID] {
        let changes = documentsByID.values.compactMap { document -> (OpenDocument.ID, OpenDocument.ID, OpenDocument)? in
            guard let rewrittenURL = FileURLRewriter.rewrittenURL(
                document.url,
                replacing: oldURL,
                with: newURL
            ), rewrittenURL != document.id else {
                return nil
            }

            let rewrittenDocument = OpenDocument(
                url: rewrittenURL,
                text: document.text,
                lastSavedText: document.lastSavedText,
                hasUserEdited: document.hasUserEdited,
                lastKnownFileSignature: document.lastKnownFileSignature,
                externalStatus: document.externalStatus
            )

            return (document.id, rewrittenURL, rewrittenDocument)
        }

        for (oldID, newID, document) in changes {
            documentsByID[oldID] = nil
            documentsByID[newID] = document

            if let session = sessionsByID.removeValue(forKey: oldID) {
                sessionsByID[newID] = session
            }
        }

        return Dictionary(uniqueKeysWithValues: changes.map { ($0.0, $0.1) })
    }

    func updateSelection(_ selectedRange: NSRange, for id: OpenDocument.ID) {
        sessionsByID[id]?.selectedRange = selectedRange
    }

    func updateScrollOrigin(_ scrollOrigin: CGPoint, for id: OpenDocument.ID) {
        sessionsByID[id]?.scrollOrigin = scrollOrigin
    }

    func snapshot(for tab: EditorTab) -> EditorTabSnapshot? {
        guard let document = documentsByID[tab.documentID] else { return nil }

        return EditorTabSnapshot(
            id: tab.id,
            documentID: tab.documentID,
            url: document.url,
            text: document.text,
            lastSavedText: document.lastSavedText,
            hasUserEdited: document.hasUserEdited,
            lastKnownFileSignature: document.lastKnownFileSignature,
            externalStatus: document.externalStatus
        )
    }
}
