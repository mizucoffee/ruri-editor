//
//  EditorOccurrenceHighlighterTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorOccurrenceHighlighterTests: XCTestCase {
    // MARK: - isIdentifierCharacter

    func testIsIdentifierCharacterAcceptsAlphanumericsUnderscoreAndDollar() {
        XCTAssertTrue(Self.isIdentifierCharacter("a"))
        XCTAssertTrue(Self.isIdentifierCharacter("Z"))
        XCTAssertTrue(Self.isIdentifierCharacter("0"))
        XCTAssertTrue(Self.isIdentifierCharacter("_"))
        XCTAssertTrue(Self.isIdentifierCharacter("$"))
        XCTAssertTrue(Self.isIdentifierCharacter("変"))
        XCTAssertTrue(Self.isIdentifierCharacter("é"))
    }

    func testIsIdentifierCharacterRejectsSeparatorsAndSurrogates() {
        XCTAssertFalse(Self.isIdentifierCharacter(" "))
        XCTAssertFalse(Self.isIdentifierCharacter("."))
        XCTAssertFalse(Self.isIdentifierCharacter("+"))
        XCTAssertFalse(Self.isIdentifierCharacter("\n"))

        let emoji = "😀" as NSString
        XCTAssertFalse(EditorOccurrenceHighlighter.isIdentifierCharacter(emoji.character(at: 0)))
        XCTAssertFalse(EditorOccurrenceHighlighter.isIdentifierCharacter(emoji.character(at: 1)))
    }

    // MARK: - identifierRange

    func testIdentifierRangeExpandsFromMiddleStartAndLastCharacter() {
        let text = "let value = 1" as NSString
        let expected = NSRange(location: 4, length: 5)

        XCTAssertEqual(EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 6), expected)
        XCTAssertEqual(EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 4), expected)
        XCTAssertEqual(EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 8), expected)
    }

    func testIdentifierRangeCoversWordsTouchingStringBoundaries() {
        let text = "first mid last" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 0),
            NSRange(location: 0, length: 5)
        )
        XCTAssertEqual(
            EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: text.length - 1),
            NSRange(location: 10, length: 4)
        )
    }

    func testIdentifierRangeIncludesUnderscoreAndDollarCharacters() {
        let text = "_leading trailing_ $dollar mixed$_1" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 0),
            NSRange(location: 0, length: 8)
        )
        XCTAssertEqual(
            EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 17),
            NSRange(location: 9, length: 9)
        )
        XCTAssertEqual(
            EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 19),
            NSRange(location: 19, length: 7)
        )
        XCTAssertEqual(
            EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 30),
            NSRange(location: 27, length: 8)
        )
    }

    func testIdentifierRangeReturnsNilOffIdentifiers() {
        let text = "foo bar" as NSString

        XCTAssertNil(EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: 3))
        XCTAssertNil(EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: -1))
        XCTAssertNil(EditorOccurrenceHighlighter.identifierRange(in: text, containingUTF16Offset: text.length))
        XCTAssertNil(EditorOccurrenceHighlighter.identifierRange(in: "" as NSString, containingUTF16Offset: 0))
    }

    // MARK: - targetIdentifierRange

    func testTargetIdentifierRangeForCaretInsideWord() {
        let text = "let value = 1" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 6, length: 0)),
            NSRange(location: 4, length: 5)
        )
    }

    func testTargetIdentifierRangeForCaretImmediatelyAfterWord() {
        let text = "value = 1" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 5, length: 0)),
            NSRange(location: 0, length: 5)
        )
    }

    func testTargetIdentifierRangeForCaretAtEndOfString() {
        let text = "value" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 5, length: 0)),
            NSRange(location: 0, length: 5)
        )
    }

    func testTargetIdentifierRangeReturnsNilForCaretBetweenSeparators() {
        let text = "a + b\n" as NSString

        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 3, length: 0))
        )
        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 6, length: 0))
        )
        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: "" as NSString, selectedRange: NSRange(location: 0, length: 0))
        )
    }

    func testTargetIdentifierRangeReturnsNilForInvalidSelection() {
        let text = "value" as NSString

        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(
                in: text,
                selectedRange: NSRange(location: NSNotFound, length: 0)
            )
        )
        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 4, length: 5))
        )
    }

    func testTargetIdentifierRangeAcceptsSelectionExactlyMatchingWord() {
        let text = "let value = value" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 4, length: 5)),
            NSRange(location: 4, length: 5)
        )
    }

    func testTargetIdentifierRangeRejectsPartialOrOverflowingSelection() {
        let text = "let value = 1" as NSString

        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 4, length: 3))
        )
        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 4, length: 7))
        )
        XCTAssertNil(
            EditorOccurrenceHighlighter.targetIdentifierRange(in: text, selectedRange: NSRange(location: 3, length: 6))
        )
    }

    // MARK: - occurrenceRanges

    func testOccurrenceRangesFindsAllWholeWordMatches() {
        let text = "foo bar foo\nbaz foo" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 1, length: 0)),
            [
                NSRange(location: 0, length: 3),
                NSRange(location: 8, length: 3),
                NSRange(location: 16, length: 3)
            ]
        )
    }

    func testOccurrenceRangesRejectsPartialWordMatches() {
        let text = "foo foobar _foo foo_ $foo barfoo foo" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            [
                NSRange(location: 0, length: 3),
                NSRange(location: 33, length: 3)
            ]
        )
    }

    func testOccurrenceRangesIsCaseSensitive() {
        let text = "Foo foo FOO foo" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 5, length: 0)),
            [
                NSRange(location: 4, length: 3),
                NSRange(location: 12, length: 3)
            ]
        )
    }

    func testOccurrenceRangesMatchesAtStringBoundariesWithoutTrailingNewline() {
        let text = "value = value" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            [
                NSRange(location: 0, length: 5),
                NSRange(location: 8, length: 5)
            ]
        )
    }

    func testOccurrenceRangesMatchesAdjacentOccurrencesAroundOperator() {
        let text = "foo+foo" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            [
                NSRange(location: 0, length: 3),
                NSRange(location: 4, length: 3)
            ]
        )
    }

    func testOccurrenceRangesIncludesSingleOccurrenceUnderCaret() {
        let text = "unique" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 3, length: 0)),
            [NSRange(location: 0, length: 6)]
        )
    }

    func testOccurrenceRangesMatchesUnicodeIdentifiers() {
        let text = "変数名 = 変数名 + café" as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 1, length: 0)),
            [
                NSRange(location: 0, length: 3),
                NSRange(location: 6, length: 3)
            ]
        )
    }

    func testOccurrenceRangesReturnsEmptyOffIdentifiersAndForEmptyText() {
        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(
                in: "a + b" as NSString,
                selectedRange: NSRange(location: 2, length: 0)
            ),
            []
        )
        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(
                in: "" as NSString,
                selectedRange: NSRange(location: 0, length: 0)
            ),
            []
        )
    }

    func testOccurrenceRangesReturnsEmptyBeyondMaximumScanLength() {
        let text = String(
            repeating: "a",
            count: EditorOccurrenceHighlighter.maximumScanUTF16Length + 1
        ) as NSString

        XCTAssertEqual(
            EditorOccurrenceHighlighter.occurrenceRanges(in: text, selectedRange: NSRange(location: 0, length: 0)),
            []
        )
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        let string = String(character) as NSString
        return EditorOccurrenceHighlighter.isIdentifierCharacter(string.character(at: 0))
    }
}
