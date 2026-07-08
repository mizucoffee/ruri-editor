//
//  ReviewZenTabKeyMatcherTests.swift
//  ruriTests
//

import AppKit
import XCTest
@testable import ruri

final class ReviewZenTabKeyMatcherTests: XCTestCase {
    func testTabWithoutModifiersMatches() {
        XCTAssertTrue(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.tab, modifierFlags: [])
        )
    }

    func testTabWithFunctionFlagMatches() {
        XCTAssertTrue(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.tab, modifierFlags: .function)
        )
    }

    func testShiftTabDoesNotMatch() {
        XCTAssertFalse(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.tab, modifierFlags: .shift)
        )
    }

    func testCommandTabDoesNotMatch() {
        XCTAssertFalse(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.tab, modifierFlags: .command)
        )
    }

    func testControlTabDoesNotMatch() {
        XCTAssertFalse(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.tab, modifierFlags: .control)
        )
    }

    func testOptionTabDoesNotMatch() {
        XCTAssertFalse(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.tab, modifierFlags: .option)
        )
    }

    func testNonTabKeyCodeDoesNotMatch() {
        XCTAssertFalse(
            ReviewZenTabKeyMatcher.matches(keyCode: KeyCode.returnKey, modifierFlags: [])
        )
    }
}
