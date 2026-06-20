//
//  CodingAgentStatus.swift
//  ruri
//

import Foundation

enum CodingAgentProvider: String, Codable, Equatable, Sendable {
    case codex
    case claude

    nonisolated var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        }
    }
}

enum CodingAgentState: String, Codable, Equatable, Sendable {
    case running
    case waiting
    case completed
    case error

    nonisolated var isUnreadEligible: Bool {
        switch self {
        case .running:
            false
        case .waiting, .completed, .error:
            true
        }
    }

    nonisolated var isNotificationEligible: Bool {
        switch self {
        case .running:
            false
        case .waiting, .completed, .error:
            true
        }
    }
}

struct CodingAgentStatus: Equatable, Sendable {
    let terminalID: TerminalTab.ID
    let provider: CodingAgentProvider
    let state: CodingAgentState
    let event: String
    let updatedAt: Date
    let workspaceRoot: URL?

    nonisolated var changeKey: String {
        "\(provider.rawValue)|\(state.rawValue)|\(event)|\(updatedAt.timeIntervalSince1970)"
    }

    nonisolated var displayTitle: String {
        provider.displayName
    }
}

struct CodingAgentTerminalStatus: Equatable, Sendable {
    let status: CodingAgentStatus
    let isUnread: Bool
}
