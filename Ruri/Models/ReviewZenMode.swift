//
//  ReviewZenMode.swift
//  ruri
//

nonisolated struct ReviewZenPaneSnapshot: Equatable, Sendable {
    var isFileTreeVisible: Bool
    var isWorktreeOverviewVisible: Bool
    var isTerminalVisible: Bool

    static let allHidden = ReviewZenPaneSnapshot(
        isFileTreeVisible: false,
        isWorktreeOverviewVisible: false,
        isTerminalVisible: false
    )
}

nonisolated enum ReviewZenTransition: Equatable, Sendable {
    case hide
    case restore(ReviewZenPaneSnapshot)
}

nonisolated struct ReviewZenModeState: Equatable, Sendable {
    private(set) var savedSnapshot: ReviewZenPaneSnapshot?

    var isActive: Bool {
        savedSnapshot != nil
    }

    mutating func toggle(current: ReviewZenPaneSnapshot) -> ReviewZenTransition {
        if let savedSnapshot {
            self.savedSnapshot = nil
            return .restore(savedSnapshot)
        }

        savedSnapshot = current
        return .hide
    }

    mutating func handleExternalPaneChange(current: ReviewZenPaneSnapshot) {
        guard isActive, current != .allHidden else { return }
        savedSnapshot = nil
    }

    mutating func handleLeaveReviewMode() -> ReviewZenPaneSnapshot? {
        defer { savedSnapshot = nil }
        return savedSnapshot
    }
}
