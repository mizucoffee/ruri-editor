//
//  FocusedPane.swift
//  ruri
//

enum FocusedPane: Equatable {
    case fileTree
    case editor
    case terminal
    case reviewDiff
}

enum FocusedResponderKind: Equatable {
    case pane(FocusedPane)
    case textInput
    case swiftUIRegion
    case none
}

enum FocusedPaneResolver {
    static func visiblePane(
        responderKind: FocusedResponderKind,
        isFileTreeEngaged: Bool,
        isFileTreeInlineEditing: Bool,
        isWindowKey: Bool
    ) -> FocusedPane? {
        guard isWindowKey else { return nil }

        switch responderKind {
        case .pane(let pane):
            return pane
        case .textInput:
            return isFileTreeInlineEditing ? .fileTree : nil
        case .swiftUIRegion:
            return isFileTreeEngaged ? .fileTree : nil
        case .none:
            return nil
        }
    }

    static func retainsFileTreeEngagement(
        responderKind: FocusedResponderKind,
        isFileTreeInlineEditing: Bool
    ) -> Bool {
        switch responderKind {
        case .pane, .none:
            return false
        case .textInput:
            return isFileTreeInlineEditing
        case .swiftUIRegion:
            return true
        }
    }
}
