//
//  EditorIndentGuideCalculatorTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorIndentGuideCalculatorTests: XCTestCase {
    func testSpaceIndentGuidesUseConfiguredWidth() {
        XCTAssertEqual(guideCount(in: "  value", tabWidth: 4), 0)
        XCTAssertEqual(guideCount(in: "    value", tabWidth: 4), 0)
        XCTAssertEqual(guideCount(in: "      value", tabWidth: 4), 1)
        XCTAssertEqual(guideCount(in: "        value", tabWidth: 4), 1)
        XCTAssertEqual(guideCount(in: "  value", tabWidth: 2), 0)
        XCTAssertEqual(guideCount(in: "   value", tabWidth: 2), 1)
    }

    func testTabIndentGuidesAdvanceToConfiguredTabStops() {
        XCTAssertEqual(guideCount(in: "\tvalue", tabWidth: 4), 0)
        XCTAssertEqual(guideCount(in: "\t\tvalue", tabWidth: 4), 1)
        XCTAssertEqual(guideCount(in: "  \tvalue", tabWidth: 4), 0)
        XCTAssertEqual(guideCount(in: "    \tvalue", tabWidth: 4), 1)
        XCTAssertEqual(guideCount(in: "\t  value", tabWidth: 4), 1)
    }

    func testGuideAtIndentBoundaryDrawsWhenLineHasNoVisibleContentThere() {
        XCTAssertEqual(guideCount(in: "    ", tabWidth: 4), 1)
        XCTAssertEqual(guideCount(in: "        ", tabWidth: 4), 2)
        XCTAssertEqual(guideCount(in: "    \n", tabWidth: 4), 1)
    }

    func testGuideCountUsesTheProvidedLineRange() {
        let text = "root\n    child\n\t\tgrandchild" as NSString
        let childLineRange = text.lineRange(for: NSRange(location: 5, length: 0))
        let grandchildLineRange = text.lineRange(for: NSRange(location: 15, length: 0))

        XCTAssertEqual(
            EditorIndentGuideCalculator.guideCount(
                in: text,
                lineRange: childLineRange,
                tabWidth: 4
            ),
            0
        )
        XCTAssertEqual(
            EditorIndentGuideCalculator.guideCount(
                in: text,
                lineRange: grandchildLineRange,
                tabWidth: 4
            ),
            1
        )
    }

    func testInvalidTabWidthDisablesGuides() {
        XCTAssertEqual(guideCount(in: "    value", tabWidth: 0), 0)
    }

    private func guideCount(in line: String, tabWidth: Int) -> Int {
        let string = line as NSString
        return EditorIndentGuideCalculator.guideCount(
            in: string,
            lineRange: NSRange(location: 0, length: string.length),
            tabWidth: tabWidth
        )
    }
}
