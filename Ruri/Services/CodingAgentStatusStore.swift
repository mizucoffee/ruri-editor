//
//  CodingAgentStatusStore.swift
//  ruri
//

import Foundation

nonisolated protocol CodingAgentStatusStoring: Sendable {
    func load(
        from statusDirectoryURL: URL?,
        openTerminalIDs: Set<TerminalTab.ID>
    ) async -> [TerminalTab.ID: CodingAgentStatus]
}

nonisolated struct CodingAgentStatusStore: CodingAgentStatusStoring, Sendable {
    nonisolated init() {}

    nonisolated func load(
        from statusDirectoryURL: URL?,
        openTerminalIDs: Set<TerminalTab.ID>
    ) async -> [TerminalTab.ID: CodingAgentStatus] {
        guard let statusDirectoryURL else { return [:] }

        return await Task.detached(priority: .userInitiated) {
            let directoryURL = statusDirectoryURL.standardizedFileURL
            let fileManager = FileManager.default
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) else {
                return [:]
            }

            var statusesByTerminalID: [TerminalTab.ID: CodingAgentStatus] = [:]
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                guard let status = Self.loadStatus(from: fileURL),
                      openTerminalIDs.contains(status.terminalID) else {
                    continue
                }

                if let existing = statusesByTerminalID[status.terminalID],
                   existing.updatedAt >= status.updatedAt {
                    continue
                }

                statusesByTerminalID[status.terminalID] = status
            }

            return statusesByTerminalID
        }.value
    }

    private nonisolated static func loadStatus(from fileURL: URL) -> CodingAgentStatus? {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(CodingAgentStatusDocument.self, from: data),
              document.version == 1,
              let terminalID = TerminalTab.ID(uuidString: document.terminalID),
              let updatedAt = ISO8601DateFormatter.ruriAgentStatusDate(from: document.updatedAt) else {
            return nil
        }

        return CodingAgentStatus(
            terminalID: terminalID,
            provider: document.provider,
            state: document.state,
            event: document.event,
            updatedAt: updatedAt,
            workspaceRoot: document.workspaceRoot.map {
                URL(filePath: $0, directoryHint: .isDirectory).standardizedFileURL
            }
        )
    }
}

private struct CodingAgentStatusDocument: Codable {
    let version: Int
    let terminalID: String
    let provider: CodingAgentProvider
    let state: CodingAgentState
    let event: String
    let updatedAt: String
    let workspaceRoot: String?
}

private extension ISO8601DateFormatter {
    static func ruriAgentStatusDate(from string: String) -> Date? {
        ruriAgentStatusWithFractionalSeconds.date(from: string)
            ?? ruriAgentStatusWithoutFractionalSeconds.date(from: string)
    }

    static let ruriAgentStatusWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let ruriAgentStatusWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
