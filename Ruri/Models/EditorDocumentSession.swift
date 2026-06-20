//
//  EditorDocumentSession.swift
//  ruri
//

import CoreGraphics
import Foundation

nonisolated final class EditorDocumentSession {
    var selectedRange = NSRange(location: 0, length: 0)
    var scrollOrigin = CGPoint.zero
    var syntaxLanguageOverride: String?
    var pendingSelectionRevealID: UUID?

    func requestSelectionReveal(_ range: NSRange) {
        selectedRange = range
        pendingSelectionRevealID = UUID()
    }

    func restoreNavigationPlace(selectedRange: NSRange, scrollOrigin: CGPoint) {
        self.selectedRange = selectedRange
        self.scrollOrigin = scrollOrigin
        pendingSelectionRevealID = UUID()
    }
}
