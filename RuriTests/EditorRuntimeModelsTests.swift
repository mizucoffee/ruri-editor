//
//  EditorRuntimeModelsTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorRuntimeModelsTests: XCTestCase {
    // MARK: - EditorFindState.matchDescription

    func testMatchDescriptionReturnsErrorMessageBeforeAnythingElse() {
        let state = makeFindState(
            query: "ruri",
            matches: [NSRange(location: 0, length: 4)],
            selectedMatchIndex: 0,
            errorMessage: "Invalid regular expression"
        )
        XCTAssertEqual(state.matchDescription, "Invalid regular expression")
    }

    func testMatchDescriptionIsEmptyForEmptyQuery() {
        let state = makeFindState(query: "")
        XCTAssertEqual(state.matchDescription, "")
    }

    func testMatchDescriptionReportsNoMatches() {
        let state = makeFindState(query: "ruri")
        XCTAssertEqual(state.matchDescription, "No matches")
    }

    func testMatchDescriptionReportsMatchCountWithoutSelection() {
        let state = makeFindState(query: "ruri", matches: makeMatches(count: 3))
        XCTAssertEqual(state.matchDescription, "3 matches")
    }

    func testMatchDescriptionReportsOneBasedSelectionPosition() {
        let state = makeFindState(query: "ruri", matches: makeMatches(count: 3), selectedMatchIndex: 1)
        XCTAssertEqual(state.matchDescription, "2 of 3")
    }

    // MARK: - EditorFindState.canNavigate

    func testCanNavigateRequiresMatchesAndNoError() {
        XCTAssertTrue(makeFindState(query: "ruri", matches: makeMatches(count: 1)).canNavigate)
        XCTAssertFalse(makeFindState(query: "ruri").canNavigate)
        XCTAssertFalse(
            makeFindState(query: "ruri", matches: makeMatches(count: 1), errorMessage: "bad pattern").canNavigate
        )
    }

    // MARK: - EditorFindState.canReplace / canReplaceAll

    func testCanReplaceAdditionallyRequiresSelectedMatch() {
        XCTAssertTrue(
            makeFindState(query: "ruri", matches: makeMatches(count: 2), selectedMatchIndex: 0).canReplace
        )
        XCTAssertFalse(makeFindState(query: "ruri", matches: makeMatches(count: 2)).canReplace)
        XCTAssertFalse(makeFindState(query: "ruri", selectedMatchIndex: 0).canReplace)
    }

    func testCanReplaceAllFollowsCanNavigate() {
        XCTAssertTrue(makeFindState(query: "ruri", matches: makeMatches(count: 2)).canReplaceAll)
        XCTAssertFalse(makeFindState(query: "ruri").canReplaceAll)
        XCTAssertFalse(
            makeFindState(query: "ruri", matches: makeMatches(count: 2), errorMessage: "bad pattern").canReplaceAll
        )
    }

    // MARK: - EditorCursorPosition.displayText

    func testCursorPositionDisplayTextFormatsLineAndColumn() {
        XCTAssertEqual(EditorCursorPosition(line: 3, column: 7).displayText, "Ln 3, Col 7")
        XCTAssertEqual(EditorCursorPosition(line: 1, column: 1).displayText, "Ln 1, Col 1")
    }

    // MARK: - EditorSyntaxLanguageState

    func testEffectiveLanguageNamePrefersOverride() {
        XCTAssertEqual(
            makeLanguageState(inferred: "java", override: "kotlin").effectiveLanguageName,
            "kotlin"
        )
        XCTAssertEqual(makeLanguageState(inferred: "java", override: nil).effectiveLanguageName, "java")
        XCTAssertNil(makeLanguageState(inferred: nil, override: nil).effectiveLanguageName)
    }

    func testEffectiveDisplayNameFallsBackToAutoDetect() {
        XCTAssertEqual(makeLanguageState(inferred: nil, override: nil).effectiveDisplayName, "Auto Detect")
        XCTAssertEqual(makeLanguageState(inferred: "java", override: nil).effectiveDisplayName, "Java")
        XCTAssertEqual(makeLanguageState(inferred: "java", override: "kotlin").effectiveDisplayName, "Kotlin")
    }

    func testSelectedLanguageNameIsTheOverride() {
        XCTAssertEqual(makeLanguageState(inferred: "java", override: "kotlin").selectedLanguageName, "kotlin")
        XCTAssertNil(makeLanguageState(inferred: "java", override: nil).selectedLanguageName)
    }

    func testAutoDisplayNameIncludesInferredLanguage() {
        XCTAssertEqual(makeLanguageState(inferred: nil, override: nil).autoDisplayName, "Auto Detect")
        XCTAssertEqual(
            makeLanguageState(inferred: "java", override: nil).autoDisplayName,
            "Auto Detect (Java)"
        )
    }

    // MARK: - Helpers

    private func makeFindState(
        query: String,
        matches: [NSRange] = [],
        selectedMatchIndex: Int? = nil,
        errorMessage: String? = nil
    ) -> EditorFindState {
        var state = EditorFindState()
        state.query = query
        state.matches = matches
        state.selectedMatchIndex = selectedMatchIndex
        state.errorMessage = errorMessage
        return state
    }

    private func makeMatches(count: Int) -> [NSRange] {
        (0..<count).map { NSRange(location: $0 * 10, length: 4) }
    }

    private func makeLanguageState(inferred: String?, override: String?) -> EditorSyntaxLanguageState {
        EditorSyntaxLanguageState(
            inferredLanguageName: inferred,
            overrideLanguageName: override,
            languageOptions: []
        )
    }
}
