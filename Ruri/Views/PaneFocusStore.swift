//
//  PaneFocusStore.swift
//  ruri
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class PaneFocusStore: ObservableObject {
    @Published private(set) var visiblePane: FocusedPane?

    private weak var window: NSWindow?
    private var firstResponderObservation: NSKeyValueObservation?
    private var keyWindowObservers: [any NSObjectProtocol] = []
    private weak var terminalPanelView: NSView?
    private weak var editorContainerView: NSView?
    private var reviewDiffHostView: () -> NSView? = { nil }
    private var editorMode: () -> EditorMode = { .edit }
    private var isFileTreeEngaged = false
    private var isFileTreeInlineEditing = false

    deinit {
        firstResponderObservation?.invalidate()
        for observer in keyWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func attach(window: NSWindow?) {
        guard self.window !== window else { return }

        firstResponderObservation?.invalidate()
        firstResponderObservation = nil
        for observer in keyWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyWindowObservers.removeAll()
        self.window = window

        guard let window else {
            reclassify()
            return
        }

        firstResponderObservation = window.observe(
            \.firstResponder,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.reclassify()
            }
        }

        let center = NotificationCenter.default
        let keyNotificationNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]
        for name in keyNotificationNames {
            let observer = center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reclassify()
                }
            }
            keyWindowObservers.append(observer)
        }

        reclassify()
    }

    func registerEditorPane(
        container: NSView,
        terminalPanel: NSView,
        reviewDiffHostView: @escaping () -> NSView?,
        editorMode: @escaping () -> EditorMode
    ) {
        editorContainerView = container
        terminalPanelView = terminalPanel
        self.reviewDiffHostView = reviewDiffHostView
        self.editorMode = editorMode
        reclassify()
    }

    func engageFileTree() {
        isFileTreeEngaged = true
        reclassify()
    }

    func setFileTreeInlineEditing(_ isEditing: Bool) {
        if isEditing {
            isFileTreeEngaged = true
        }
        isFileTreeInlineEditing = isEditing
        reclassify()
    }

    private func reclassify() {
        let responderKind = Self.classifyResponder(
            window?.firstResponder,
            terminalPanel: terminalPanelView,
            reviewDiffHost: reviewDiffHostView(),
            editorContainer: editorContainerView,
            editorMode: editorMode()
        )
        if !FocusedPaneResolver.retainsFileTreeEngagement(
            responderKind: responderKind,
            isFileTreeInlineEditing: isFileTreeInlineEditing
        ) {
            isFileTreeEngaged = false
        }

        let pane = FocusedPaneResolver.visiblePane(
            responderKind: responderKind,
            isFileTreeEngaged: isFileTreeEngaged,
            isFileTreeInlineEditing: isFileTreeInlineEditing,
            isWindowKey: window?.isKeyWindow ?? false
        )
        if visiblePane != pane {
            visiblePane = pane
        }
    }

    static func classifyResponder(
        _ responder: NSResponder?,
        terminalPanel: NSView?,
        reviewDiffHost: NSView?,
        editorContainer: NSView?,
        editorMode: EditorMode
    ) -> FocusedResponderKind {
        guard let view = responder as? NSView else { return .none }

        if let terminalPanel, view.isDescendant(of: terminalPanel) {
            return .pane(.terminal)
        }

        if let reviewDiffHost, view.isDescendant(of: reviewDiffHost) {
            return .pane(.reviewDiff)
        }

        if let editorContainer, view.isDescendant(of: editorContainer) {
            return .pane(editorMode == .review ? .reviewDiff : .editor)
        }

        if view is NSText || view is NSTextField {
            return .textInput
        }

        return .swiftUIRegion
    }
}
