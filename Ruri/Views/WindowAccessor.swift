//
//  WindowAccessor.swift
//  ruri
//
//  Created by Codex on 2026/06/17.
//

import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowAccessorView {
        let view = WindowAccessorView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowAccessorView, context: Context) {
        nsView.onWindowChange = onWindowChange
        nsView.notifyWindowChange()
    }
}

final class WindowAccessorView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        notifyWindowChange()
    }

    func notifyWindowChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWindowChange?(self.window)
        }
    }
}
