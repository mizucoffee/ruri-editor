//
//  EditorFindBarCommandActionTests.swift
//  ruriTests
//

import AppKit
import XCTest
@testable import ruri

final class EditorFindBarCommandActionTests: XCTestCase {
    func testSearchReturnMovesToNextMatch() {
        XCTAssertEqual(
            EditorFindBarCommandAction.action(
                for: .search,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: []
            ),
            .next
        )
    }

    func testSearchShiftReturnMovesToPreviousMatch() {
        XCTAssertEqual(
            EditorFindBarCommandAction.action(
                for: .search,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: .shift
            ),
            .previous
        )
    }

    func testSearchShiftKeypadReturnMovesToPreviousMatch() {
        XCTAssertEqual(
            EditorFindBarCommandAction.action(
                for: .search,
                commandSelector: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                modifierFlags: .shift
            ),
            .previous
        )
    }

    func testSearchCommandModifiedReturnIsNotHandled() {
        XCTAssertNil(
            EditorFindBarCommandAction.action(
                for: .search,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertNil(
            EditorFindBarCommandAction.action(
                for: .search,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: .control
            )
        )
        XCTAssertNil(
            EditorFindBarCommandAction.action(
                for: .search,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: .option
            )
        )
    }

    func testReplacementReturnReplacesSelectedMatch() {
        XCTAssertEqual(
            EditorFindBarCommandAction.action(
                for: .replacement,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: []
            ),
            .replace
        )
    }

    func testReplacementShiftReturnDoesNotMoveToPreviousMatch() {
        XCTAssertEqual(
            EditorFindBarCommandAction.action(
                for: .replacement,
                commandSelector: #selector(NSResponder.insertNewline(_:)),
                modifierFlags: .shift
            ),
            .replace
        )
        XCTAssertNil(
            EditorFindBarCommandAction.action(
                for: .replacement,
                commandSelector: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                modifierFlags: .shift
            )
        )
    }
}
