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
    func terminalRuntime(_ runtime: TerminalRuntime, didRequestSelectTabAtShortcutNumber number: Int)
    func terminalRuntime(_ runtime: TerminalRuntime, didRequestOpenFile request: TerminalFileOpenRequest)
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
    private var terminalViewDelegateProxy: RuriTerminalViewDelegateProxy?

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
        terminalView.allowMouseReporting = false
        terminalView.processDelegate = self
        let terminalViewDelegateProxy = RuriTerminalViewDelegateProxy(terminalView: terminalView)
        terminalViewDelegateProxy.openLink = { [weak self] link, params in
            self?.openTerminalLink(link, params: params)
        }
        self.terminalViewDelegateProxy = terminalViewDelegateProxy
        terminalView.terminalDelegate = terminalViewDelegateProxy
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
        terminalView.terminalDelegate = nil
        terminalViewDelegateProxy = nil
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

    private func openTerminalLink(_ link: String, params: [String: String]) {
        if let request = TerminalLinkResolver.fileOpenRequest(
            for: link,
            cwd: cwd,
            environment: environment
        ) {
            delegate?.terminalRuntime(self, didRequestOpenFile: request)
            return
        }

        if let url = URL(string: link), url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
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
            case .selectTab(let number):
                self.delegate?.terminalRuntime(self, didRequestSelectTabAtShortcutNumber: number)
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

private final class RuriTerminalViewDelegateProxy: TerminalViewDelegate {
    weak var terminalView: LocalProcessTerminalView?
    var openLink: ((String, [String: String]) -> Void)?

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        terminalView?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        terminalView?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        terminalView?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        terminalView?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        terminalView?.scrolled(source: source, position: position)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let openLink {
            openLink(link, params)
        } else if let url = URL(string: link), url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        NSSound.beep()
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        terminalView?.clipboardCopy(source: source, content: content)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        terminalView?.rangeChanged(source: source, startY: startY, endY: endY)
    }
}

enum TerminalLinkResolver {
    static func fileOpenRequest(
        for link: String,
        cwd: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> TerminalFileOpenRequest? {
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLink.isEmpty else { return nil }

        let parsed = parsedPathAndLine(from: trimmedLink)
        let rawPath = parsed.path

        if let url = URL(string: rawPath),
           let scheme = url.scheme,
           scheme != "file" {
            return nil
        }

        guard let fileURL = resolvedFileURL(
            from: rawPath,
            cwd: cwd,
            environment: environment,
            fileManager: fileManager
        ) else {
            return nil
        }

        return TerminalFileOpenRequest(url: fileURL, lineNumber: parsed.lineNumber)
    }

    private static func parsedPathAndLine(from link: String) -> (path: String, lineNumber: Int?) {
        if let exactURL = URL(string: link),
           exactURL.scheme == "file",
           FileManager.default.fileExists(atPath: exactURL.path(percentEncoded: false)) {
            return (link, nil)
        }

        let nsLink = link as NSString
        let pattern = #"^(.*?)(?::([1-9][0-9]*))(?:[:.]([1-9][0-9]*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: link,
                range: NSRange(location: 0, length: nsLink.length)
              ),
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return (link, nil)
        }

        let path = nsLink.substring(with: match.range(at: 1))
        let lineNumber = Int(nsLink.substring(with: match.range(at: 2)))
        return (path, lineNumber)
    }

    private static func resolvedFileURL(
        from path: String,
        cwd: URL,
        environment: [String: String],
        fileManager: FileManager
    ) -> URL? {
        let expandedPath = expandedLeadingPathComponent(path, environment: environment)
        let candidateURL: URL

        if let url = URL(string: expandedPath),
           url.scheme == "file" {
            candidateURL = url.standardizedFileURL
        } else if expandedPath.hasPrefix("/") {
            candidateURL = URL(filePath: expandedPath).standardizedFileURL
        } else {
            candidateURL = cwd.appending(path: expandedPath).standardizedFileURL
        }

        guard fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) else {
            return nil
        }

        return candidateURL
    }

    private static func expandedLeadingPathComponent(
        _ path: String,
        environment: [String: String]
    ) -> String {
        if path == "~" || path.hasPrefix("~/") {
            let home = environment["HOME"] ?? NSHomeDirectory()
            return home + path.dropFirst()
        }

        guard path.hasPrefix("$") else {
            return path
        }

        let variableName = path.dropFirst().prefix { character in
            character == "_" || character.isLetter || character.isNumber
        }
        guard !variableName.isEmpty,
              let value = environment[String(variableName)] else {
            return path
        }

        return value + path.dropFirst(1 + variableName.count)
    }
}

enum TerminalKeyCommandMatcher {
    enum TerminalShortcut: Equatable {
        case newTab
        case closeTab
        case selectTab(Int)
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
        case "0":
            return .selectTab(0)
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return charactersIgnoringModifiers.flatMap(Int.init).map(TerminalShortcut.selectTab)
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

    static func tabShortcutNumber(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Int? {
        guard case .selectTab(let number) = terminalShortcut(
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags
        ) else {
            return nil
        }

        return number
    }

    static func tabShortcutNumber(_ event: NSEvent) -> Int? {
        tabShortcutNumber(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }
}
