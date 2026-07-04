//
//  CodingAgentStatusStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class CodingAgentStatusStoreTests: XCTestCase {
    private let fileManager = FileManager.default

    func testLoadsStatusForOpenTerminalID() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directoryURL) }
        let terminalID = UUID()

        try writeStatus(
            terminalID: terminalID,
            provider: "codex",
            state: "running",
            event: "PreToolUse",
            updatedAt: "2026-06-19T12:34:56Z",
            to: directoryURL.appending(path: "status.json")
        )

        let statuses = await CodingAgentStatusStore().load(
            from: directoryURL,
            openTerminalIDs: [terminalID]
        )

        XCTAssertEqual(statuses[terminalID]?.provider, .codex)
        XCTAssertEqual(statuses[terminalID]?.state, .running)
        XCTAssertEqual(statuses[terminalID]?.event, "PreToolUse")
    }

    func testIgnoresMalformedAndUnknownStatusDocuments() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directoryURL) }
        let terminalID = UUID()

        try "{ invalid".write(
            to: directoryURL.appending(path: "malformed.json"),
            atomically: true,
            encoding: .utf8
        )
        try writeStatus(
            terminalID: terminalID,
            provider: "other",
            state: "running",
            event: "PreToolUse",
            updatedAt: "2026-06-19T12:34:56Z",
            to: directoryURL.appending(path: "unknown-provider.json")
        )
        try writeStatus(
            terminalID: terminalID,
            provider: "codex",
            state: "busy",
            event: "PreToolUse",
            updatedAt: "2026-06-19T12:34:56Z",
            to: directoryURL.appending(path: "unknown-state.json")
        )

        let statuses = await CodingAgentStatusStore().load(
            from: directoryURL,
            openTerminalIDs: [terminalID]
        )

        XCTAssertTrue(statuses.isEmpty)
    }

    func testIgnoresStatusForClosedTerminalID() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directoryURL) }

        try writeStatus(
            terminalID: UUID(),
            provider: "claude",
            state: "waiting",
            event: "PermissionRequest",
            updatedAt: "2026-06-19T12:34:56Z",
            to: directoryURL.appending(path: "status.json")
        )

        let statuses = await CodingAgentStatusStore().load(
            from: directoryURL,
            openTerminalIDs: [UUID()]
        )

        XCTAssertTrue(statuses.isEmpty)
    }

    func testKeepsLatestStatusForTerminalID() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: directoryURL) }
        let terminalID = UUID()

        try writeStatus(
            terminalID: terminalID,
            provider: "codex",
            state: "running",
            event: "PreToolUse",
            updatedAt: "2026-06-19T12:34:56Z",
            to: directoryURL.appending(path: "old.json")
        )
        try writeStatus(
            terminalID: terminalID,
            provider: "codex",
            state: "completed",
            event: "Stop",
            updatedAt: "2026-06-19T12:35:56Z",
            to: directoryURL.appending(path: "new.json")
        )

        let statuses = await CodingAgentStatusStore().load(
            from: directoryURL,
            openTerminalIDs: [terminalID]
        )

        XCTAssertEqual(statuses[terminalID]?.state, .completed)
        XCTAssertEqual(statuses[terminalID]?.event, "Stop")
    }

    private func writeStatus(
        terminalID: UUID,
        provider: String,
        state: String,
        event: String,
        updatedAt: String,
        to fileURL: URL
    ) throws {
        let text = """
        {
          "version": 1,
          "terminalID": "\(terminalID.uuidString)",
          "provider": "\(provider)",
          "state": "\(state)",
          "event": "\(event)",
          "updatedAt": "\(updatedAt)",
          "workspaceRoot": "/tmp/project"
        }
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }
}
