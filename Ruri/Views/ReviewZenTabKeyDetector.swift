//
//  ReviewZenTabKeyDetector.swift
//  ruri
//

import AppKit
import SwiftUI

struct ReviewZenTabKeyDetector: NSViewRepresentable {
    let isEnabled: () -> Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, action: action)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.isEnabled = isEnabled
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var isEnabled: () -> Bool
        var action: () -> Void
        weak var hostView: NSView?

        private var monitor: Any?

        init(isEnabled: @escaping () -> Bool, action: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.action = action
        }

        deinit {
            remove()
        }

        func install() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func remove() {
            guard let monitor else { return }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window = hostView?.window,
                  event.window === window,
                  !Self.hasMarkedText(),
                  ReviewZenTabKeyMatcher.matches(
                      keyCode: event.keyCode,
                      modifierFlags: event.modifierFlags
                  ),
                  isEnabled() else {
                return event
            }

            action()
            return nil
        }

        private static func hasMarkedText() -> Bool {
            guard let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient else {
                return false
            }

            return inputClient.hasMarkedText()
        }
    }
}

enum ReviewZenTabKeyMatcher {
    static func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == KeyCode.tab else { return false }

        return modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])
            .isEmpty
    }
}
