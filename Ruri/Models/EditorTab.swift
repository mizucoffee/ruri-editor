//
//  EditorTab.swift
//  ruri
//

import Foundation

nonisolated enum OpenDocumentExternalStatus: Equatable, Sendable {
    case normal
    case externallyModified
    case deleted
    case conflict

    var displayDescription: String? {
        switch self {
        case .normal:
            nil
        case .externallyModified:
            "File was modified outside ruri"
        case .deleted:
            "File was deleted outside ruri"
        case .conflict:
            "File changed outside ruri while this tab has unsaved edits"
        }
    }
}

nonisolated struct OpenDocument: Identifiable, Equatable, Sendable {
    typealias ID = URL

    let id: ID
    var text: String
    var lastSavedText: String
    var hasUserEdited: Bool
    var lastKnownFileSignature: ProjectFileSignature?
    var externalStatus: OpenDocumentExternalStatus

    init(
        url: URL,
        text: String,
        lastSavedText: String,
        hasUserEdited: Bool = false,
        lastKnownFileSignature: ProjectFileSignature? = nil,
        externalStatus: OpenDocumentExternalStatus = .normal
    ) {
        self.id = url
        self.text = text
        self.lastSavedText = lastSavedText
        self.hasUserEdited = hasUserEdited
        self.lastKnownFileSignature = lastKnownFileSignature
        self.externalStatus = externalStatus
    }

    var url: URL {
        id
    }

    var hasUnsavedChanges: Bool {
        text != lastSavedText
    }

    var canSave: Bool {
        hasUnsavedChanges || externalStatus == .deleted
    }
}

nonisolated struct SaveConflictConfirmation: Identifiable, Equatable, Sendable {
    let workspaceID: ProjectWorkspaceSnapshot.ID
    let tabID: EditorTab.ID
    let url: URL

    var id: EditorTab.ID {
        tabID
    }

    var fileName: String {
        url.lastPathComponent
    }
}

nonisolated struct EditorTab: Identifiable, Equatable, Sendable {
    let id: UUID
    var documentID: OpenDocument.ID

    init(
        id: UUID = UUID(),
        documentID: OpenDocument.ID
    ) {
        self.id = id
        self.documentID = documentID
    }
}

nonisolated struct EditorTabSnapshot: Identifiable, Equatable, Sendable {
    let id: EditorTab.ID
    let documentID: OpenDocument.ID
    let url: URL
    let text: String
    let lastSavedText: String
    let hasUserEdited: Bool
    let lastKnownFileSignature: ProjectFileSignature?
    let externalStatus: OpenDocumentExternalStatus

    var hasUnsavedChanges: Bool {
        text != lastSavedText
    }

    var canSave: Bool {
        hasUnsavedChanges || externalStatus == .deleted
    }
}
