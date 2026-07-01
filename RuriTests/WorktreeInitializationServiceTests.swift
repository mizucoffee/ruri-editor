//
//  WorktreeInitializationServiceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class WorktreeInitializationServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testRunExecutesCommandInWorktreeRoot() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let service = WorktreeInitializationService(shellPath: "/bin/sh", timeout: 5)

        try await service.run(command: "pwd > init-pwd.txt", in: rootURL)

        let pwd = try String(
            contentsOf: rootURL.appending(path: "init-pwd.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(normalizedPath(pwd), normalizedPath(rootURL.path(percentEncoded: false)))
    }

    func testRunReportsNonZeroExitOutput() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let service = WorktreeInitializationService(shellPath: "/bin/sh", timeout: 5)

        do {
            try await service.run(command: "echo setup failed >&2; exit 7", in: rootURL)
            XCTFail("Expected initialization to fail.")
        } catch WorktreeInitializationError.commandFailed(let exitCode, let output) {
            XCTAssertEqual(exitCode, 7)
            XCTAssertTrue(output.contains("setup failed"))
        }
    }

    func testRunSkipsEmptyCommand() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let service = WorktreeInitializationService(shellPath: "/bin/sh", timeout: 5)

        try await service.run(command: "   \n", in: rootURL)

        let contents = try fileManager.contentsOfDirectory(
            atPath: rootURL.path(percentEncoded: false)
        )
        XCTAssertEqual(contents, [])
    }

    func testRunReportsProcessFailureWhenShellCannotLaunch() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let service = WorktreeInitializationService(
            shellPath: "/tmp/ruri-missing-shell",
            timeout: 5
        )

        do {
            try await service.run(command: "echo setup", in: rootURL)
            XCTFail("Expected process failure.")
        } catch WorktreeInitializationError.processFailed(let message) {
            XCTAssertTrue(message.contains("not executable"))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func normalizedPath(_ path: String) -> String {
        var path = NSString(string: path).standardizingPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
