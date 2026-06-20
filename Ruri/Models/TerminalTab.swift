//
//  TerminalTab.swift
//  ruri
//

import Foundation

enum TerminalTabStatus: Equatable, Sendable {
    case running
    case exited(exitCode: Int32?)

    var isRunning: Bool {
        if case .running = self {
            return true
        }

        return false
    }
}

enum TerminalTabKind: Equatable, Sendable {
    case shell
    case run(configurationID: RunConfiguration.ID)

    var isRun: Bool {
        if case .run = self {
            return true
        }

        return false
    }
}

struct TerminalTab: Identifiable, Equatable, Sendable {
    typealias ID = UUID

    let id: ID
    let defaultTitle: String
    var title: String
    let cwd: URL
    let shellPath: String
    let launchArguments: [String]
    let kind: TerminalTabKind
    var status: TerminalTabStatus

    init(
        id: ID = UUID(),
        defaultTitle: String,
        cwd: URL,
        shellPath: String,
        launchArguments: [String] = [],
        kind: TerminalTabKind = .shell,
        status: TerminalTabStatus = .running
    ) {
        self.id = id
        self.defaultTitle = defaultTitle
        self.title = defaultTitle
        self.cwd = cwd.standardizedFileURL
        self.shellPath = shellPath
        self.launchArguments = launchArguments
        self.kind = kind
        self.status = status
    }

    func snapshot(agentStatus: CodingAgentTerminalStatus? = nil) -> TerminalTabSnapshot {
        TerminalTabSnapshot(
            id: id,
            title: title.isEmpty ? defaultTitle : title,
            defaultTitle: defaultTitle,
            cwd: cwd,
            shellPath: shellPath,
            launchArguments: launchArguments,
            kind: kind,
            status: status,
            agentStatus: agentStatus
        )
    }
}

struct TerminalTabSnapshot: Identifiable, Equatable, Sendable {
    let id: TerminalTab.ID
    let title: String
    let defaultTitle: String
    let cwd: URL
    let shellPath: String
    let launchArguments: [String]
    let kind: TerminalTabKind
    let status: TerminalTabStatus
    let agentStatus: CodingAgentTerminalStatus?

    init(
        id: TerminalTab.ID,
        title: String,
        defaultTitle: String,
        cwd: URL,
        shellPath: String,
        launchArguments: [String],
        kind: TerminalTabKind,
        status: TerminalTabStatus,
        agentStatus: CodingAgentTerminalStatus? = nil
    ) {
        self.id = id
        self.title = title
        self.defaultTitle = defaultTitle
        self.cwd = cwd.standardizedFileURL
        self.shellPath = shellPath
        self.launchArguments = launchArguments
        self.kind = kind
        self.status = status
        self.agentStatus = agentStatus
    }

    var isRunning: Bool {
        status.isRunning
    }

    var isRun: Bool {
        kind.isRun
    }
}

struct TerminalWorkspaceSnapshot: Identifiable, Equatable, Sendable {
    let id: ProjectWorkspaceSnapshot.ID
    let rootURL: URL
    let tabs: [TerminalTabSnapshot]
    let selectedTabID: TerminalTab.ID?

    init(
        id: ProjectWorkspaceSnapshot.ID,
        rootURL: URL,
        tabs: [TerminalTabSnapshot],
        selectedTabID: TerminalTab.ID?
    ) {
        self.id = id.standardizedFileURL
        self.rootURL = rootURL.standardizedFileURL
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }

    var displayName: String {
        rootURL.lastPathComponent
    }

    var displayPath: String {
        rootURL.path(percentEncoded: false)
    }
}

struct TerminalCloseConfirmation: Identifiable, Equatable, Sendable {
    let tabID: TerminalTab.ID
    let title: String

    var id: TerminalTab.ID {
        tabID
    }
}

struct TerminalFocusRequest: Equatable, Sendable {
    let id = UUID()
    let tabID: TerminalTab.ID
}
