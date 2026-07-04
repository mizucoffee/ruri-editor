//
//  NSRangeClampingTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class NSRangeClampingTests: XCTestCase {
    func testClampedMovesNotFoundLocationToEnd() {
        let range = NSRange(location: NSNotFound, length: 3).clamped(toUTF16Length: 10)

        XCTAssertEqual(range, NSRange(location: 10, length: 0))
    }

    func testClampedClampsNegativeLocationToZero() {
        let range = NSRange(location: -4, length: 3).clamped(toUTF16Length: 10)

        XCTAssertEqual(range, NSRange(location: 0, length: 3))
    }

    func testClampedTrimsLengthToRemainingText() {
        let range = NSRange(location: 8, length: 5).clamped(toUTF16Length: 10)

        XCTAssertEqual(range, NSRange(location: 8, length: 2))
    }

    func testClampedCollapsesToZeroInEmptyText() {
        let range = NSRange(location: 4, length: 5).clamped(toUTF16Length: 0)

        XCTAssertEqual(range, NSRange(location: 0, length: 0))
    }

    func testClampedKeepsInBoundsRangeUnchanged() {
        let range = NSRange(location: 2, length: 3).clamped(toUTF16Length: 10)

        XCTAssertEqual(range, NSRange(location: 2, length: 3))
    }

    func testClampedCollapsesLocationBeyondLengthToEnd() {
        let range = NSRange(location: 15, length: 2).clamped(toUTF16Length: 10)

        XCTAssertEqual(range, NSRange(location: 10, length: 0))
    }

    func testClampedClampsNegativeLengthToZero() {
        let range = NSRange(location: 2, length: -5).clamped(toUTF16Length: 10)

        XCTAssertEqual(range, NSRange(location: 2, length: 0))
    }

    func testClampedMovesNotFoundLocationToZeroInEmptyText() {
        let range = NSRange(location: NSNotFound, length: 0).clamped(toUTF16Length: 0)

        XCTAssertEqual(range, NSRange(location: 0, length: 0))
    }
}
