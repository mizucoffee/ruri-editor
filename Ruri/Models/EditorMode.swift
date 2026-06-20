//
//  EditorMode.swift
//  ruri
//

import Foundation

nonisolated enum EditorMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case edit
    case review

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .edit:
            "Edit"
        case .review:
            "Review"
        }
    }
}
