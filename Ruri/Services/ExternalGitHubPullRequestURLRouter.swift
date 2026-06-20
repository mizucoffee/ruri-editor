//
//  ExternalGitHubPullRequestURLRouter.swift
//  ruri
//
//  Created by Codex on 2026/06/17.
//

import AppKit
import Foundation

@MainActor
final class ExternalGitHubPullRequestURLRouter {
    static let shared = ExternalGitHubPullRequestURLRouter()

    private var editors: [WeakEditorState] = []
    private var shouldCloseTransientEmptyWindows = false

    private init() {}

    func register(_ editor: EditorState) {
        register(editor, window: nil)
    }

    func register(_ editor: EditorState, window: NSWindow?) {
        pruneEditors()
        if let existing = editors.first(where: { $0.editor === editor }) {
            if let window {
                existing.window = window
            }
            closeTransientEmptyWindowsIfNeeded()
            return
        }

        editors.append(WeakEditorState(editor: editor, window: window))
        closeTransientEmptyWindowsIfNeeded()
    }

    func unregister(_ editor: EditorState) {
        editors.removeAll { $0.editor == nil || $0.editor === editor }
    }

    func open(_ url: URL) async {
        shouldCloseTransientEmptyWindows = true
        defer {
            closeTransientEmptyWindowsIfNeeded()
        }

        guard let reference = GitHubExternalURLParser.pullRequestReference(from: url) else {
            await fallbackEditor()?.openExternalGitHubPullRequestURL(url)
            return
        }

        for editor in liveEditors() {
            if await editor.canOpenExternalGitHubPullRequest(reference) {
                await editor.openExternalGitHubPullRequest(reference)
                return
            }
        }

        await fallbackEditor()?.openExternalGitHubPullRequestURL(url)
    }

    private func fallbackEditor() -> EditorState? {
        liveEditors().first
    }

    private func liveEditors() -> [EditorState] {
        pruneEditors()
        return editors.compactMap(\.editor)
    }

    private func pruneEditors() {
        editors.removeAll { $0.editor == nil }
    }

    private func closeTransientEmptyWindowsIfNeeded() {
        guard shouldCloseTransientEmptyWindows else { return }

        let liveEditors = liveEditors()
        guard liveEditors.contains(where: { $0.hasOpenedProject }) else {
            return
        }

        var didCloseWindow = false
        for registration in editors {
            guard let editor = registration.editor,
                  !editor.hasOpenedProject,
                  let window = registration.window else {
                continue
            }

            window.close()
            didCloseWindow = true
        }

        if didCloseWindow {
            pruneEditors()
        }

        shouldCloseTransientEmptyWindows = false
    }
}

private final class WeakEditorState {
    weak var editor: EditorState?
    weak var window: NSWindow?

    init(editor: EditorState, window: NSWindow?) {
        self.editor = editor
        self.window = window
    }
}
