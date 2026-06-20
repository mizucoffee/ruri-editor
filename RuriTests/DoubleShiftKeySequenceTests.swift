//
//  DoubleShiftKeySequenceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class DoubleShiftKeySequenceTests: XCTestCase {
    func testConsecutiveShiftDownsWithinIntervalTriggerAction() {
        var sequence = DoubleShiftKeySequence()

        XCTAssertFalse(sequence.registerShiftDown(at: 10.0))
        XCTAssertTrue(sequence.registerShiftDown(at: 10.4))
    }

    func testInterveningKeyInputCancelsPendingShift() {
        var sequence = DoubleShiftKeySequence()

        XCTAssertFalse(sequence.registerShiftDown(at: 10.0))
        sequence.cancelPendingShift()

        XCTAssertFalse(sequence.registerShiftDown(at: 10.2))
        XCTAssertTrue(sequence.registerShiftDown(at: 10.3))
    }

    func testShiftDownOutsideIntervalStartsNewSequence() {
        var sequence = DoubleShiftKeySequence()

        XCTAssertFalse(sequence.registerShiftDown(at: 10.0))
        XCTAssertFalse(sequence.registerShiftDown(at: 10.6))
        XCTAssertTrue(sequence.registerShiftDown(at: 10.8))
    }
}
