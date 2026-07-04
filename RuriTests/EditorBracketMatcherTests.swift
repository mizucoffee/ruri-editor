//
//  EditorBracketMatcherTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorBracketMatcherTests: XCTestCase {
    // MARK: - bracketKind

    func testBracketKindRecognizesSupportedBrackets() {
        XCTAssertEqual(Self.bracketKind("(")?.isOpening, true)
        XCTAssertEqual(Self.bracketKind(")")?.isOpening, false)
        XCTAssertEqual(Self.bracketKind("[")?.isOpening, true)
        XCTAssertEqual(Self.bracketKind("]")?.isOpening, false)
        XCTAssertEqual(Self.bracketKind("{")?.isOpening, true)
        XCTAssertEqual(Self.bracketKind("}")?.isOpening, false)
    }

    func testBracketKindRejectsOtherCharacters() {
        XCTAssertNil(Self.bracketKind("a"))
        XCTAssertNil(Self.bracketKind("<"))
        XCTAssertNil(Self.bracketKind(">"))
        XCTAssertNil(Self.bracketKind(" "))
        XCTAssertNil(Self.bracketKind("\n"))

        let emoji = "😀" as NSString
        XCTAssertNil(EditorBracketMatcher.bracketKind(of: emoji.character(at: 0)))
        XCTAssertNil(EditorBracketMatcher.bracketKind(of: emoji.character(at: 1)))
    }

    // MARK: - targetBracketOffset

    func testTargetBracketOffsetPrefersCharacterAtCaret() {
        let text = ")(" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 1, length: 0)),
            1
        )
    }

    func testTargetBracketOffsetFallsBackToPrecedingCharacter() {
        let text = "()" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 2, length: 0)),
            1
        )
    }

    func testTargetBracketOffsetReturnsNilAwayFromBrackets() {
        let text = "( a )" as NSString

        XCTAssertNil(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 2, length: 0))
        )
        XCTAssertNil(
            EditorBracketMatcher.targetBracketOffset(in: "" as NSString, selectedRange: NSRange(location: 0, length: 0))
        )
        XCTAssertNil(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 9, length: 0))
        )
    }

    func testTargetBracketOffsetAcceptsSingleBracketSelectionOnly() {
        let text = "(ab)" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 0, length: 1)),
            0
        )
        XCTAssertNil(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 0, length: 2))
        )
        XCTAssertNil(
            EditorBracketMatcher.targetBracketOffset(in: text, selectedRange: NSRange(location: 1, length: 1))
        )
    }

    // MARK: - matchedBracketRanges

    func testMatchedBracketRangesMatchesForwardFromOpeningBracket() {
        let text = "call(a, b)" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 4, length: 0)),
            [NSRange(location: 4, length: 1), NSRange(location: 9, length: 1)]
        )
    }

    func testMatchedBracketRangesMatchesBackwardFromClosingBracket() {
        let text = "call(a, b)" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 10, length: 0)),
            [NSRange(location: 4, length: 1), NSRange(location: 9, length: 1)]
        )
    }

    func testMatchedBracketRangesSupportsAllBracketKinds() {
        let square = "a[0]" as NSString
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: square, selectedRange: NSRange(location: 1, length: 0)),
            [NSRange(location: 1, length: 1), NSRange(location: 3, length: 1)]
        )

        let curly = "{ x }" as NSString
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: curly, selectedRange: NSRange(location: 5, length: 0)),
            [NSRange(location: 0, length: 1), NSRange(location: 4, length: 1)]
        )
    }

    func testMatchedBracketRangesRespectsNesting() {
        let text = "((a)(b))" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            [NSRange(location: 0, length: 1), NSRange(location: 7, length: 1)]
        )
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 1, length: 0)),
            [NSRange(location: 1, length: 1), NSRange(location: 3, length: 1)]
        )
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 5, length: 0)),
            [NSRange(location: 4, length: 1), NSRange(location: 6, length: 1)]
        )
    }

    func testMatchedBracketRangesIgnoresOtherBracketKindsWhileMatching() {
        let text = "([)]" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)]
        )
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 1, length: 0)),
            [NSRange(location: 1, length: 1), NSRange(location: 3, length: 1)]
        )
    }

    func testMatchedBracketRangesReturnsEmptyWithoutCounterpart() {
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(
                in: "(a" as NSString,
                selectedRange: NSRange(location: 0, length: 0)
            ),
            []
        )
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(
                in: "a)" as NSString,
                selectedRange: NSRange(location: 2, length: 0)
            ),
            []
        )
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(
                in: "((a)" as NSString,
                selectedRange: NSRange(location: 0, length: 0)
            ),
            []
        )
    }

    func testMatchedBracketRangesReturnsEmptyAwayFromBrackets() {
        let text = "let value = 1" as NSString

        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 5, length: 0)),
            []
        )
        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 0, length: 3)),
            []
        )
    }

    func testMatchedBracketRangesReturnsEmptyBeyondMaximumScanLength() {
        let text = ("(" + String(
            repeating: "a",
            count: EditorBracketMatcher.maximumScanUTF16Length
        ) + ")") as NSString

        XCTAssertEqual(
            EditorBracketMatcher.matchedBracketRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            []
        )
    }

    private static func bracketKind(_ character: Character) -> EditorBracketMatcher.BracketKind? {
        let string = String(character) as NSString
        return EditorBracketMatcher.bracketKind(of: string.character(at: 0))
    }
}
