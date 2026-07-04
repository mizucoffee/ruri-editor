//
//  CodingAgentNotificationRouter.swift
//  ruri
//

import AppKit
import Foundation

@MainActor
final class CodingAgentNotificationRouter {
    static let shared = CodingAgentNotificationRouter()

    private var registrations: [WeakCodingAgentNotificationTarget] = []

    private init() {}

    func register(editor: EditorViewModel, terminalState: TerminalViewModel) {
        register(editor: editor, terminalState: terminalState, window: nil)
    }

    func register(editor: EditorViewModel, terminalState: TerminalViewModel, window: NSWindow?) {
        pruneRegistrations()
        if let existing = registrations.first(where: { $0.editor === editor && $0.terminalState === terminalState }) {
            if let window {
                existing.window = window
            }
            return
        }

        registrations.append(
            WeakCodingAgentNotificationTarget(
                editor: editor,
                terminalState: terminalState,
                window: window
            )
        )
    }

    func unregister(terminalState: TerminalViewModel) {
        registrations.removeAll { $0.terminalState == nil || $0.terminalState === terminalState }
    }

    @discardableResult
    func openNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo[CodingAgentNotificationUserInfoKey.kind] as? String == CodingAgentNotificationUserInfoValue.kind,
              let terminalIDString = userInfo[CodingAgentNotificationUserInfoKey.terminalID] as? String,
              let terminalID = TerminalTab.ID(uuidString: terminalIDString) else {
            return false
        }

        return openTerminal(terminalID)
    }

    @discardableResult
    func openTerminal(_ terminalID: TerminalTab.ID) -> Bool {
        pruneRegistrations()

        for registration in registrations {
            guard let editor = registration.editor,
                  let terminalState = registration.terminalState,
                  let workspaceID = terminalState.workspaceID(containing: terminalID) else {
                continue
            }

            editor.selectProject(workspaceID)
            terminalState.revealTab(terminalID, in: workspaceID, requestsFocus: true)
            registration.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        return false
    }

    private func pruneRegistrations() {
        registrations.removeAll { $0.editor == nil || $0.terminalState == nil }
    }
}

private final class WeakCodingAgentNotificationTarget {
    weak var editor: EditorViewModel?
    weak var terminalState: TerminalViewModel?
    weak var window: NSWindow?

    init(editor: EditorViewModel, terminalState: TerminalViewModel, window: NSWindow?) {
        self.editor = editor
        self.terminalState = terminalState
        self.window = window
    }
}
