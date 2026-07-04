//
//  TerminalKeyCommandMatcherTests.swift
//  ruriTests
//

import AppKit
import XCTest
@testable import ruri

final class TerminalKeyCommandMatcherTests: XCTestCase {
    func testCommandTMatchesNewTerminalTabShortcut() {
        XCTAssertTrue(
            TerminalKeyCommandMatcher.isNewTerminalTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: .command
            )
        )
    }

    func testCommandShiftTDoesNotMatchNewTerminalTabShortcut() {
        XCTAssertFalse(
            TerminalKeyCommandMatcher.isNewTerminalTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.command, .shift]
            )
        )
    }

    func testCommandOptionTDoesNotMatchNewTerminalTabShortcut() {
        XCTAssertFalse(
            TerminalKeyCommandMatcher.isNewTerminalTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: [.command, .option]
            )
        )
    }

    func testPlainTDoesNotMatchNewTerminalTabShortcut() {
        XCTAssertFalse(
            TerminalKeyCommandMatcher.isNewTerminalTabShortcut(
                charactersIgnoringModifiers: "t",
                modifierFlags: []
            )
        )
    }

    func testCommandWMatchesCloseTerminalTabShortcut() {
        XCTAssertTrue(
            TerminalKeyCommandMatcher.isCloseTerminalTabShortcut(
                charactersIgnoringModifiers: "w",
                modifierFlags: .command
            )
        )
    }

    func testCommandShiftWDoesNotMatchCloseTerminalTabShortcut() {
        XCTAssertFalse(
            TerminalKeyCommandMatcher.isCloseTerminalTabShortcut(
                charactersIgnoringModifiers: "w",
                modifierFlags: [.command, .shift]
            )
        )
    }

    func testCommandOptionWDoesNotMatchCloseTerminalTabShortcut() {
        XCTAssertFalse(
            TerminalKeyCommandMatcher.isCloseTerminalTabShortcut(
                charactersIgnoringModifiers: "w",
                modifierFlags: [.command, .option]
            )
        )
    }

    func testPlainWDoesNotMatchCloseTerminalTabShortcut() {
        XCTAssertFalse(
            TerminalKeyCommandMatcher.isCloseTerminalTabShortcut(
                charactersIgnoringModifiers: "w",
                modifierFlags: []
            )
        )
    }

    func testCommandNumberMatchesTabShortcutNumber() {
        XCTAssertEqual(
            TerminalKeyCommandMatcher.tabShortcutNumber(
                charactersIgnoringModifiers: "1",
                modifierFlags: .command
            ),
            1
        )
        XCTAssertEqual(
            TerminalKeyCommandMatcher.tabShortcutNumber(
                charactersIgnoringModifiers: "9",
                modifierFlags: .command
            ),
            9
        )
    }

    func testCommandZeroMatchesLastTabShortcutNumber() {
        XCTAssertEqual(
            TerminalKeyCommandMatcher.tabShortcutNumber(
                charactersIgnoringModifiers: "0",
                modifierFlags: .command
            ),
            0
        )
    }

    func testModifiedCommandNumberDoesNotMatchTabShortcutNumber() {
        XCTAssertNil(
            TerminalKeyCommandMatcher.tabShortcutNumber(
                charactersIgnoringModifiers: "1",
                modifierFlags: [.command, .shift]
            )
        )
        XCTAssertNil(
            TerminalKeyCommandMatcher.tabShortcutNumber(
                charactersIgnoringModifiers: "1",
                modifierFlags: [.command, .option]
            )
        )
    }

    func testPlainNumberDoesNotMatchTabShortcutNumber() {
        XCTAssertNil(
            TerminalKeyCommandMatcher.tabShortcutNumber(
                charactersIgnoringModifiers: "1",
                modifierFlags: []
            )
        )
    }
}
