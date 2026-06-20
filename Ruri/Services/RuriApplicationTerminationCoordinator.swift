//
//  RuriApplicationTerminationCoordinator.swift
//  ruri
//

import AppKit

@MainActor
final class RuriApplicationTerminationCoordinator {
    static let shared = RuriApplicationTerminationCoordinator()

    typealias QuitConfirmation = @MainActor () -> Bool

    private var editors: [WeakTerminationEditorState] = []
    private let quitConfirmation: QuitConfirmation

    init(quitConfirmation: @escaping QuitConfirmation = RuriApplicationTerminationCoordinator.presentQuitConfirmation) {
        self.quitConfirmation = quitConfirmation
    }

    func register(_ editor: EditorState) {
        pruneEditors()
        guard !editors.contains(where: { $0.editor === editor }) else { return }
        editors.append(WeakTerminationEditorState(editor: editor))
    }

    func unregister(_ editor: EditorState) {
        editors.removeAll { $0.editor == nil || $0.editor === editor }
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        guard shouldPromptForQuitConfirmation else {
            return .terminateNow
        }

        return quitConfirmation() ? .terminateNow : .terminateCancel
    }

    var shouldPromptForQuitConfirmation: Bool {
        pruneEditors()
        return editors.contains { $0.editor?.hasOpenedProject == true }
    }

    private func pruneEditors() {
        editors.removeAll { $0.editor == nil }
    }

    private static func presentQuitConfirmation() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit Ruri?"
        alert.informativeText = "A project is currently open. Quitting will close all Ruri windows."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }
}

private final class WeakTerminationEditorState {
    weak var editor: EditorState?

    init(editor: EditorState) {
        self.editor = editor
    }
}
