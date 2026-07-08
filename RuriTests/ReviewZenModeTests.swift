//
//  ReviewZenModeTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class ReviewZenModeTests: XCTestCase {
    private let visibleSnapshot = ReviewZenPaneSnapshot(
        isFileTreeVisible: true,
        isWorktreeOverviewVisible: false,
        isTerminalVisible: true
    )

    func testToggleFromInactiveSavesSnapshotAndHides() {
        var state = ReviewZenModeState()

        let transition = state.toggle(current: visibleSnapshot)

        XCTAssertEqual(transition, .hide)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.savedSnapshot, visibleSnapshot)
    }

    func testToggleFromActiveRestoresSavedSnapshotAndDeactivates() {
        var state = ReviewZenModeState()
        _ = state.toggle(current: visibleSnapshot)

        let transition = state.toggle(current: .allHidden)

        XCTAssertEqual(transition, .restore(visibleSnapshot))
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.savedSnapshot)
    }

    func testExternalPaneChangeDeactivatesWhenPaneBecomesVisible() {
        var state = ReviewZenModeState()
        _ = state.toggle(current: visibleSnapshot)

        var changed = ReviewZenPaneSnapshot.allHidden
        changed.isTerminalVisible = true
        state.handleExternalPaneChange(current: changed)

        XCTAssertFalse(state.isActive)
    }

    func testExternalPaneChangeKeepsActiveWhileAllHidden() {
        var state = ReviewZenModeState()
        _ = state.toggle(current: visibleSnapshot)

        state.handleExternalPaneChange(current: .allHidden)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.savedSnapshot, visibleSnapshot)
    }

    func testExternalPaneChangeWhileInactiveIsNoOp() {
        var state = ReviewZenModeState()

        state.handleExternalPaneChange(current: visibleSnapshot)

        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.savedSnapshot)
    }

    func testLeaveReviewModeReturnsSnapshotOnceAndClears() {
        var state = ReviewZenModeState()
        _ = state.toggle(current: visibleSnapshot)

        XCTAssertEqual(state.handleLeaveReviewMode(), visibleSnapshot)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.handleLeaveReviewMode())
    }

    func testLeaveReviewModeWhileInactiveReturnsNil() {
        var state = ReviewZenModeState()

        XCTAssertNil(state.handleLeaveReviewMode())
    }

    func testToggleWithAllHiddenSnapshotRestoresAllHidden() {
        var state = ReviewZenModeState()

        XCTAssertEqual(state.toggle(current: .allHidden), .hide)
        XCTAssertEqual(state.toggle(current: .allHidden), .restore(.allHidden))
    }
}
