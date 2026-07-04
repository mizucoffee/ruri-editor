//
//  ProjectTextSearchSnippetHighlighterTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class ProjectTextSearchSnippetHighlighterTests: XCTestCase {
    func testLineLocalRunsClipsAndShiftsFileRuns() {
        let result = makeResult(lineText: "let value = 42", matchLocation: 104, lineMatchLocation: 4)
        let fileRuns = [
            SyntaxHighlightRun(location: 90, length: 15, role: .comment),
            SyntaxHighlightRun(location: 100, length: 3, role: .keyword),
            SyntaxHighlightRun(location: 112, length: 2, role: .number),
            SyntaxHighlightRun(location: 130, length: 4, role: .string)
        ]

        let localRuns = ProjectTextSearchSnippetHighlighter.lineLocalRuns(from: fileRuns, for: result)

        XCTAssertEqual(
            localRuns,
            [
                SyntaxHighlightRun(location: 0, length: 5, role: .comment),
                SyntaxHighlightRun(location: 0, length: 3, role: .keyword),
                SyntaxHighlightRun(location: 12, length: 2, role: .number)
            ]
        )
    }

    func testLineLocalRunsReturnsEmptyWhenNoRunTouchesLine() {
        let result = makeResult(lineText: "let value = 42", matchLocation: 104, lineMatchLocation: 4)
        let fileRuns = [SyntaxHighlightRun(location: 0, length: 50, role: .comment)]

        XCTAssertTrue(ProjectTextSearchSnippetHighlighter.lineLocalRuns(from: fileRuns, for: result).isEmpty)
    }

    private func makeResult(
        lineText: String,
        matchLocation: Int,
        lineMatchLocation: Int
    ) -> ProjectTextSearchResult {
        ProjectTextSearchResult(
            url: URL(filePath: "/tmp/Sample.swift"),
            relativePath: "Sample.swift",
            fileName: "Sample.swift",
            lineNumber: 5,
            column: lineMatchLocation + 1,
            lineText: lineText,
            matchRange: TextRange(location: matchLocation, length: 5),
            lineMatchRange: TextRange(location: lineMatchLocation, length: 5)
        )
    }
}
