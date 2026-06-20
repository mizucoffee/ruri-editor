//
//  CodeUsageResultTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class CodeUsageResultTests: XCTestCase {
    func testSortsNonTestFilesBeforeTestFiles() {
        let results = CodeUsageResult.sorted([
            CodeUsageResult(
                url: URL(filePath: "/tmp/project/Tests/Helper.swift"),
                relativePath: "Tests/Helper.swift",
                fileName: "Helper.swift",
                lineNumber: 1,
                column: 1,
                lineText: "needle",
                matchRange: TextRange(location: 0, length: 1),
                lineMatchRange: TextRange(location: 0, length: 1)
            ),
            CodeUsageResult(
                url: URL(filePath: "/tmp/project/Sources/Main.swift"),
                relativePath: "Sources/Main.swift",
                fileName: "Main.swift",
                lineNumber: 1,
                column: 1,
                lineText: "needle",
                matchRange: TextRange(location: 0, length: 1),
                lineMatchRange: TextRange(location: 0, length: 1)
            ),
            CodeUsageResult(
                url: URL(filePath: "/tmp/project/App.swift"),
                relativePath: "App.swift",
                fileName: "App.swift",
                lineNumber: 1,
                column: 1,
                lineText: "needle",
                matchRange: TextRange(location: 0, length: 1),
                lineMatchRange: TextRange(location: 0, length: 1)
            )
        ])

        XCTAssertEqual(results.map(\.relativePath), ["App.swift", "Sources/Main.swift", "Tests/Helper.swift"])
        XCTAssertEqual(results.map(\.isInTestDirectory), [false, false, true])
    }
}
