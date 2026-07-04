//
//  EditorLineNumberingTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorLineNumberingTests: XCTestCase {
    // MARK: - lineCount(in:)

    func testEmptyStringHasOneLine() {
        XCTAssertEqual(EditorLineNumbering.lineCount(in: ""), 1)
    }

    func testSingleLineWithoutNewlineHasOneLine() {
        XCTAssertEqual(EditorLineNumbering.lineCount(in: "a"), 1)
    }

    func testLineFeedSeparatedLinesAreCounted() {
        XCTAssertEqual(EditorLineNumbering.lineCount(in: "a\nb"), 2)
        XCTAssertEqual(EditorLineNumbering.lineCount(in: "\n\n"), 3)
    }

    func testTrailingNewlineCountsAsEmptyLastLine() {
        XCTAssertEqual(EditorLineNumbering.lineCount(in: "a\n"), 2)
    }

    func testCRLFCountsAsSingleLineBreak() {
        XCTAssertEqual(EditorLineNumbering.lineCount(in: "a\r\nb"), 2)
    }

    func testLoneCarriageReturnIsNotCountedAsLineBreak() {
        // 現行仕様の固定: lineCount は "\n" のみを数えるため、CR 単独(旧Mac改行)は行区切りにならない。
        // 一方 lineRange は NSString.lineRange(for:) に委譲され CR も行区切りとして扱うので、
        // CR 単独を含むテキストでは両者の行認識がずれる。エディタの改行は LF/CRLF 前提。
        XCTAssertEqual(EditorLineNumbering.lineCount(in: "a\rb"), 1)
    }

    // MARK: - lineRange(forLineNumber:in:)

    func testEmptyStringReturnsZeroRange() {
        XCTAssertEqual(
            EditorLineNumbering.lineRange(forLineNumber: 1, in: ""),
            NSRange(location: 0, length: 0)
        )
    }

    func testLineRangesIncludeLineTerminators() {
        let text = "ab\ncd\nef" as NSString
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 1, in: text), NSRange(location: 0, length: 3))
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 2, in: text), NSRange(location: 3, length: 3))
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 3, in: text), NSRange(location: 6, length: 2))
    }

    func testLineNumberBelowOneClampsToFirstLine() {
        let text = "ab\ncd\nef" as NSString
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 0, in: text), NSRange(location: 0, length: 3))
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: -5, in: text), NSRange(location: 0, length: 3))
    }

    func testLineNumberAboveLineCountClampsToLastLine() {
        let text = "ab\ncd\nef" as NSString
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 99, in: text), NSRange(location: 6, length: 2))
    }

    func testTrailingNewlineYieldsEmptyLastLineRange() {
        let text = "ab\n" as NSString
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 2, in: text), NSRange(location: 3, length: 0))
    }

    func testCRLFLineRangeIncludesBothTerminatorCharacters() {
        let text = "ab\r\ncd" as NSString
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 1, in: text), NSRange(location: 0, length: 4))
        XCTAssertEqual(EditorLineNumbering.lineRange(forLineNumber: 2, in: text), NSRange(location: 4, length: 2))
    }
}
