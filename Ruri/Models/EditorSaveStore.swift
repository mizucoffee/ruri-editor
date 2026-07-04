//
//  EditorSaveStore.swift
//  ruri
//

import Foundation

struct EditorSaveStore {
    enum SaveAction: Equatable {
        case skip
        case conflict(recordedConfirmation: Bool)
        case write(textToSave: String)
    }

    private(set) var pendingConflictConfirmation: SaveConflictConfirmation?

    mutating func beginSave(
        document: OpenDocument?,
        tabID: EditorTab.ID,
        workspaceID: ProjectWorkspaceSnapshot.ID,
        allowingConflictOverwrite: Bool,
        presentsConflictConfirmation: Bool
    ) -> SaveAction {
        guard let document else { return .skip }

        guard document.externalStatus != .conflict || allowingConflictOverwrite else {
            guard presentsConflictConfirmation else {
                return .conflict(recordedConfirmation: false)
            }

            pendingConflictConfirmation = SaveConflictConfirmation(
                workspaceID: workspaceID,
                tabID: tabID,
                url: document.url
            )
            return .conflict(recordedConfirmation: true)
        }

        return .write(textToSave: document.text)
    }

    mutating func takeConfirmationForOverwrite() -> SaveConflictConfirmation? {
        guard let confirmation = pendingConflictConfirmation else { return nil }

        pendingConflictConfirmation = nil
        return confirmation
    }

    mutating func cancelConflict() {
        pendingConflictConfirmation = nil
    }
}
