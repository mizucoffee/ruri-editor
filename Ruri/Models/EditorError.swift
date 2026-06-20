//
//  EditorError.swift
//  ruri
//

import Foundation

struct EditorError: Identifiable, Equatable {
    let id: UUID
    let message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }

    init(_ error: Error) {
        self.init(message: error.localizedDescription)
    }
}
