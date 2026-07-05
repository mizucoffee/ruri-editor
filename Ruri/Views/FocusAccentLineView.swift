//
//  FocusAccentLineView.swift
//  ruri
//

import AppKit

final class FocusAccentLineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    func setVisible(_ isVisible: Bool) {
        let targetAlpha: CGFloat = isVisible ? 1 : 0
        guard alphaValue != targetAlpha else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = targetAlpha
        }
    }
}
