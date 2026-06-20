//
//  FileTreePathFormatterTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class FileTreePathFormatterTests: XCTestCase {
    func testAbsolutePathUsesStandardizedDecodedPath() {
        let url = URL(filePath: "/tmp/ruri/Sources/../Sources/App File.swift")

        XCTAssertEqual(
            FileTreePathFormatter.absolutePath(for: url),
            "/tmp/ruri/Sources/App File.swift"
        )
    }

    func testRelativePathReturnsNestedPathInsideProject() {
        let projectURL = URL(filePath: "/tmp/ruri")
        let fileURL = URL(filePath: "/tmp/ruri/Sources/App.swift")

        XCTAssertEqual(
            FileTreePathFormatter.relativePath(for: fileURL, projectURL: projectURL),
            "Sources/App.swift"
        )
    }

    func testRelativePathReturnsDotForProjectRoot() {
        let projectURL = URL(filePath: "/tmp/ruri")

        XCTAssertEqual(
            FileTreePathFormatter.relativePath(for: projectURL, projectURL: projectURL),
            "."
        )
    }

    func testRelativePathReturnsNilOutsideProject() {
        let projectURL = URL(filePath: "/tmp/ruri")
        let fileURL = URL(filePath: "/tmp/other/App.swift")

        XCTAssertNil(
            FileTreePathFormatter.relativePath(for: fileURL, projectURL: projectURL)
        )
    }
}
