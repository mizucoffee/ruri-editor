//
//  CodePreviewControllerTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class CodePreviewControllerTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSetRequestLoadsDocumentWithSyntaxRuns() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Sample.swift")
        let text = "let answer = 42\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let controller = CodePreviewController()
        controller.setRequest(makeRequest(url: fileURL))

        try await TestSupport.waitUntil("preview document") {
            controller.document != nil
        }

        let document = try XCTUnwrap(controller.document)
        XCTAssertEqual(document.text, text)
        XCTAssertEqual(document.languageName, "swift")
        XCTAssertFalse(document.syntaxRuns.isEmpty)
        XCTAssertFalse(controller.isLoading)
        XCTAssertNil(controller.failure)
    }

    func testReplacedRequestPublishesLatestDocument() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstURL = rootURL.appending(path: "First.swift")
        let secondURL = rootURL.appending(path: "Second.swift")
        try "let first = 1\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "let second = 2\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let controller = CodePreviewController()
        controller.setRequest(makeRequest(url: firstURL))
        controller.setRequest(makeRequest(url: secondURL))

        try await TestSupport.waitUntil("preview document") {
            controller.document != nil
        }

        XCTAssertEqual(controller.document?.request.url, secondURL)
    }

    func testNonUTF8FileFailsAsUnreadable() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "binary.dat")
        try Data([0xFF, 0xFE, 0xFD, 0xC3, 0x28]).write(to: fileURL)

        let controller = CodePreviewController()
        controller.setRequest(makeRequest(url: fileURL))

        try await TestSupport.waitUntil("preview failure") {
            controller.failure != nil
        }

        XCTAssertEqual(controller.failure, .unreadable)
        XCTAssertNil(controller.document)
        XCTAssertFalse(controller.isLoading)
    }

    func testMissingFileFailsAsUnreadable() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let controller = CodePreviewController()
        controller.setRequest(makeRequest(url: rootURL.appending(path: "missing.swift")))

        try await TestSupport.waitUntil("preview failure") {
            controller.failure != nil
        }

        XCTAssertEqual(controller.failure, .unreadable)
    }

    func testOversizedFileFailsAsTooLarge() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Large.swift")
        try "let oversized = true\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let controller = CodePreviewController(maximumUTF16Length: 8)
        controller.setRequest(makeRequest(url: fileURL))

        try await TestSupport.waitUntil("preview failure") {
            controller.failure != nil
        }

        XCTAssertEqual(controller.failure, .fileTooLarge)
        XCTAssertNil(controller.document)
    }

    func testMatchRangeBeyondFileLengthStillLoadsDocument() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Short.swift")
        try "let short = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let controller = CodePreviewController()
        controller.setRequest(makeRequest(url: fileURL, location: 10_000, length: 50))

        try await TestSupport.waitUntil("preview document") {
            controller.document != nil
        }

        XCTAssertNil(controller.failure)
    }

    func testCachedFileServesFollowUpRequestSynchronously() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Cached.swift")
        try "let cached = true\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let controller = CodePreviewController()
        controller.setRequest(makeRequest(url: fileURL, location: 0, length: 3))

        try await TestSupport.waitUntil("preview document") {
            controller.document != nil
        }

        let followUpRequest = makeRequest(url: fileURL, location: 4, length: 6)
        controller.setRequest(followUpRequest)

        XCTAssertEqual(controller.document?.request, followUpRequest)
        XCTAssertFalse(controller.isLoading)
    }

    func testResetDiscardsCacheAndReloadsChangedFile() async throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Changing.swift")
        try "let before = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let controller = CodePreviewController()
        let request = makeRequest(url: fileURL)
        controller.setRequest(request)

        try await TestSupport.waitUntil("preview document") {
            controller.document != nil
        }

        try "let after = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        controller.reset()

        XCTAssertNil(controller.document)

        controller.setRequest(request)
        try await TestSupport.waitUntil("reloaded preview document") {
            controller.document != nil
        }

        XCTAssertEqual(controller.document?.text, "let after = 2\n")
    }

    private func makeRequest(url: URL, location: Int = 0, length: Int = 3) -> CodePreviewRequest {
        CodePreviewRequest(
            url: url,
            matchRange: TextRange(location: location, length: length),
            lineNumber: 1
        )
    }
}
