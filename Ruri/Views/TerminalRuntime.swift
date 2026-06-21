//
//  TerminalRuntime.swift
//  ruri
//

import AppKit
import SwiftTerm

@MainActor
protocol TerminalRuntimeDelegate: AnyObject {
    func terminalRuntime(_ runtime: TerminalRuntime, didUpdateTitle title: String)
    func terminalRuntime(_ runtime: TerminalRuntime, didTerminateWithExitCode exitCode: Int32?)
    func terminalRuntimeDidRequestNewTab(_ runtime: TerminalRuntime)
    func terminalRuntimeDidRequestCloseTab(_ runtime: TerminalRuntime)
}

@MainActor
final class TerminalRuntime: NSObject, LocalProcessTerminalViewDelegate {
    let workspaceID: ProjectWorkspaceSnapshot.ID
    let tabID: TerminalTab.ID
    let terminalView: LocalProcessTerminalView

    weak var delegate: TerminalRuntimeDelegate?

    private let cwd: URL
    private let shellPath: String
    private let launchArguments: [String]
    private let environment: [String: String]
    private let agentStatusDirectoryURL: URL?
    private let agentStatusHookURL: URL?
    private let launchConfiguration: TerminalShellLaunchConfiguration
    private var isInvalidated = false
    private var keyDownMonitor: Any?

    init(
        workspaceID: ProjectWorkspaceSnapshot.ID,
        tab: TerminalTabSnapshot,
        agentStatusDirectoryURL: URL?,
        agentStatusHookURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.workspaceID = workspaceID
        self.tabID = tab.id
        self.cwd = tab.cwd.standardizedFileURL
        self.shellPath = tab.shellPath
        self.launchArguments = tab.launchArguments
        self.environment = environment
        self.agentStatusDirectoryURL = agentStatusDirectoryURL?.standardizedFileURL
        self.agentStatusHookURL = (agentStatusHookURL ?? TerminalRuntime.defaultAgentStatusHookURL())?.standardizedFileURL
        self.launchConfiguration = TerminalShellLaunchConfiguration(shellPath: tab.shellPath)
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        super.init()

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.processDelegate = self
        installKeyDownMonitor()
        terminalView.startProcess(
            executable: launchConfiguration.executable,
            args: launchArguments.isEmpty ? launchConfiguration.arguments : launchArguments,
            environment: terminalEnvironment(),
            execName: launchConfiguration.execName,
            currentDirectory: cwd.path(percentEncoded: false)
        )
    }

    var isRunning: Bool {
        terminalView.process?.running ?? false
    }

    func terminate() {
        guard isRunning else { return }
        terminalView.terminate()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        terminalView.processDelegate = nil
        terminate()
        terminalView.removeFromSuperview()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        delegate?.terminalRuntime(self, didUpdateTitle: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        delegate?.terminalRuntime(self, didTerminateWithExitCode: exitCode)
    }

    private func terminalEnvironment() -> [String] {
        var values = environment
        values["SHELL"] = shellPath
        values["PWD"] = cwd.path(percentEncoded: false)
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        values["RURI_TERMINAL_TAB_ID"] = tabID.uuidString
        values["RURI_WORKTREE_ROOT"] = cwd.path(percentEncoded: false)
        if let agentStatusDirectoryURL {
            values["RURI_AGENT_STATUS_DIR"] = agentStatusDirectoryURL.path(percentEncoded: false)
        }
        if let agentStatusHookURL {
            values["RURI_AGENT_STATUS_HOOK"] = agentStatusHookURL.path(percentEncoded: false)
        }

        return values.map { key, value in "\(key)=\(value)" }
    }

    private static func defaultAgentStatusHookURL(bundle: Bundle = .main) -> URL? {
        bundle.url(
            forResource: "ruri-agent-status-hook",
            withExtension: "sh"
        ) ?? bundle.url(
            forResource: "ruri-agent-status-hook",
            withExtension: "sh",
            subdirectory: "Scripts"
        ) ?? bundle.url(
            forResource: "ruri-agent-status-hook",
            withExtension: "sh",
            subdirectory: "Resources/Scripts"
        )
    }

    private func installKeyDownMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.shouldHandleTerminalShortcut(event) else {
                return event
            }

            switch TerminalKeyCommandMatcher.terminalShortcut(for: event) {
            case .newTab:
                self.delegate?.terminalRuntimeDidRequestNewTab(self)
            case .closeTab:
                self.delegate?.terminalRuntimeDidRequestCloseTab(self)
            case nil:
                return event
            }
            return nil
        }
    }

    private func shouldHandleTerminalShortcut(_ event: NSEvent) -> Bool {
        guard TerminalKeyCommandMatcher.terminalShortcut(for: event) != nil,
              event.window === terminalView.window else {
            return false
        }

        guard let firstResponder = event.window?.firstResponder else {
            return false
        }

        if firstResponder === terminalView {
            return true
        }

        guard let firstResponderView = firstResponder as? NSView else {
            return false
        }

        return firstResponderView.isDescendant(of: terminalView)
    }
}

enum TerminalKeyCommandMatcher {
    enum TerminalShortcut: Equatable {
        case newTab
        case closeTab
    }

    static func terminalShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> TerminalShortcut? {
        let relevantModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard relevantModifiers == .command else { return nil }

        switch charactersIgnoringModifiers?.lowercased() {
        case "t":
            return .newTab
        case "w":
            return .closeTab
        default:
            return nil
        }
    }

    static func terminalShortcut(for event: NSEvent) -> TerminalShortcut? {
        terminalShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    static func isNewTerminalTabShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        terminalShortcut(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        ) == .newTab
    }

    static func isNewTerminalTabShortcut(_ event: NSEvent) -> Bool {
        terminalShortcut(for: event) == .newTab
    }

    static func isCloseTerminalTabShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        terminalShortcut(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        ) == .closeTab
    }

    static func isCloseTerminalTabShortcut(_ event: NSEvent) -> Bool {
        terminalShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) == .closeTab
    }
}
