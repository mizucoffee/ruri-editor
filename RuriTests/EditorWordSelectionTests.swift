//
//  EditorWordSelectionTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorWordSelectionTests: XCTestCase {
    private static let dottedText = "editor.gitSnapshot" as NSString
    private static let dottedFallback = NSRange(location: 0, length: 18)

    // MARK: - Double click (zero-length proposed range)

    func testDoubleClickInsideFirstSegmentSelectsOnlyThatSegment() {
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 2, length: 0)),
            NSRange(location: 0, length: 6)
        )
    }

    func testDoubleClickInsideSecondSegmentSelectsOnlyThatSegment() {
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 10, length: 0)),
            NSRange(location: 7, length: 11)
        )
    }

    func testDoubleClickAtTrailingWordBoundarySelectsPrecedingSegment() {
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 6, length: 0)),
            NSRange(location: 0, length: 6)
        )
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 18, length: 0)),
            NSRange(location: 7, length: 11)
        )
    }

    func testDoubleClickOnNonIdentifierCharacterReturnsFallback() {
        let text = "a (b) c" as NSString
        let fallback = NSRange(location: 2, length: 1)

        XCTAssertEqual(
            EditorWordSelection.wordSelectionRange(
                in: text,
                proposedRange: NSRange(location: 2, length: 0),
                fallback: fallback
            ),
            fallback
        )
    }

    func testDoubleClickOnWhitespaceReturnsFallback() {
        let text = "let  value" as NSString
        let fallback = NSRange(location: 3, length: 2)

        XCTAssertEqual(
            EditorWordSelection.wordSelectionRange(
                in: text,
                proposedRange: NSRange(location: 4, length: 0),
                fallback: fallback
            ),
            fallback
        )
    }

    func testDoubleClickSelectsIdentifierWithUnderscoreDollarAndNonASCII() {
        let text = "$snake_case2 変数名" as NSString

        XCTAssertEqual(
            EditorWordSelection.wordSelectionRange(
                in: text,
                proposedRange: NSRange(location: 5, length: 0),
                fallback: NSRange(location: 0, length: 12)
            ),
            NSRange(location: 0, length: 12)
        )
        XCTAssertEqual(
            EditorWordSelection.wordSelectionRange(
                in: text,
                proposedRange: NSRange(location: 14, length: 0),
                fallback: NSRange(location: 13, length: 3)
            ),
            NSRange(location: 13, length: 3)
        )
    }

    // MARK: - Drag extension (non-zero proposed range)

    func testDragAcrossDotSnapsToWordBoundariesOnBothEnds() {
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 2, length: 8)),
            NSRange(location: 0, length: 18)
        )
    }

    func testDragWithinSingleSegmentSelectsThatSegment() {
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 8, length: 2)),
            NSRange(location: 7, length: 11)
        )
    }

    func testDragEndingOnNonIdentifierUsesFallbackEnd() {
        let text = "editor.gitSnapshot + 1" as NSString
        let fallback = NSRange(location: 0, length: 20)

        XCTAssertEqual(
            EditorWordSelection.wordSelectionRange(
                in: text,
                proposedRange: NSRange(location: 2, length: 17),
                fallback: fallback
            ),
            NSRange(location: 0, length: 20)
        )
    }

    // MARK: - Invalid input

    func testOutOfBoundsProposedRangeReturnsFallback() {
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: 0, length: 99)),
            Self.dottedFallback
        )
        XCTAssertEqual(
            Self.wordSelectionRange(proposedRange: NSRange(location: NSNotFound, length: 0)),
            Self.dottedFallback
        )
    }

    private static func wordSelectionRange(proposedRange: NSRange) -> NSRange {
        EditorWordSelection.wordSelectionRange(
            in: dottedText,
            proposedRange: proposedRange,
            fallback: dottedFallback
        )
    }
}
