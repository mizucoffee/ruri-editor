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
}
