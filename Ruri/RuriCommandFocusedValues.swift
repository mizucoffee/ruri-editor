//
//  RuriCommandFocusedValues.swift
//  ruri
//

import SwiftUI

private struct RuriOpenFolderCommandActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RuriToggleTerminalOverviewCommandActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RuriToggleReviewZenCommandActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var ruriOpenFolderCommandAction: (() -> Void)? {
        get { self[RuriOpenFolderCommandActionKey.self] }
        set { self[RuriOpenFolderCommandActionKey.self] = newValue }
    }

    var ruriToggleTerminalOverviewCommandAction: (() -> Void)? {
        get { self[RuriToggleTerminalOverviewCommandActionKey.self] }
        set { self[RuriToggleTerminalOverviewCommandActionKey.self] = newValue }
    }

    var ruriToggleReviewZenCommandAction: (() -> Void)? {
        get { self[RuriToggleReviewZenCommandActionKey.self] }
        set { self[RuriToggleReviewZenCommandActionKey.self] = newValue }
    }
}
