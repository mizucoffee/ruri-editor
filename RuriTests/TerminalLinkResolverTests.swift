//
//  TerminalLinkResolverTests.swift
//  RuriTests
//

import XCTest
@testable import ruri

final class TerminalLinkResolverTests: XCTestCase {
    func testResolvesRelativePathAgainstCwd() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appending(path: "Sources/App.swift")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)

        let request = TerminalLinkResolver.fileOpenRequest(
            for: "Sources/App.swift",
            cwd: rootURL
        )

        XCTAssertEqual(request, TerminalFileOpenRequest(url: fileURL))
    }

    func testResolvesLineSuffix() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appending(path: "Sources/App.swift")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)

        let request = TerminalLinkResolver.fileOpenRequest(
            for: "Sources/App.swift:42:7",
            cwd: rootURL
        )

        XCTAssertEqual(request, TerminalFileOpenRequest(url: fileURL, lineNumber: 42))
    }

    func testResolvesFileURL() throws {
        let rootURL = try makeTemporaryDirectory()
        let fileURL = rootURL.appending(path: "App.swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)

        let request = TerminalLinkResolver.fileOpenRequest(
            for: fileURL.absoluteString,
            cwd: rootURL
        )

        XCTAssertEqual(request, TerminalFileOpenRequest(url: fileURL))
    }

    func testIgnoresNonFileURL() throws {
        let rootURL = try makeTemporaryDirectory()

        let request = TerminalLinkResolver.fileOpenRequest(
            for: "https://example.com/Sources/App.swift",
            cwd: rootURL
        )

        XCTAssertNil(request)
    }

    func testReturnsNilForMissingFile() throws {
        let rootURL = try makeTemporaryDirectory()

        let request = TerminalLinkResolver.fileOpenRequest(
            for: "Sources/Missing.swift:12",
            cwd: rootURL
        )

        XCTAssertNil(request)
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory()
    }
}
