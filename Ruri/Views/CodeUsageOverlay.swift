//
//  CodeUsageOverlay.swift
//  ruri
//

import AppKit
import SwiftUI

struct CodeUsageOverlay: View {
    @ObservedObject var viewModel: CodeUsageViewModel
    let openResult: (CodeUsageResult) -> Void

    var body: some View {
        Group {
            if viewModel.isPresented {
                ZStack {
                    Color.black
                        .opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            viewModel.dismiss()
                        }

                    panel
                }
                .background(keyMonitor)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: viewModel.isPresented)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header

            Divider()

            resultArea
                .frame(height: viewModel.results.isEmpty ? 96 : 360)
        }
        .frame(width: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
        }
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(viewModel.title)
                .font(.system(size: 18, weight: .semibold))

            Spacer(minLength: 0)

            Text(viewModel.summaryDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var resultArea: some View {
        if viewModel.results.isEmpty {
            statusRow(AppText.codeUsageNoResults)
        } else {
            resultList
        }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.results) { result in
                        resultRow(result)
                            .id(result.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedResultID) { _, selectedID in
                guard let selectedID else { return }

                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func resultRow(_ result: CodeUsageResult) -> some View {
        Button {
            open(result)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    Text(result.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(":\(result.lineNumber)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text(result.displayParentPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(result.lineNumber)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 42, alignment: .trailing)

                    snippetText(for: result)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(selectionBackground(for: result))
        }
        .buttonStyle(.plain)
    }

    private func snippetText(for result: CodeUsageResult) -> Text {
        let line = result.lineText as NSString
        let clampedRange = result.lineMatchRange.nsRange.clamped(toUTF16Length: line.length)
        guard clampedRange.length > 0 else {
            return Text(verbatim: result.lineText)
        }

        let prefix = line.substring(with: NSRange(location: 0, length: clampedRange.location))
        let match = line.substring(with: clampedRange)
        let suffixLocation = NSMaxRange(clampedRange)
        let suffix = line.substring(
            with: NSRange(location: suffixLocation, length: line.length - suffixLocation)
        )

        return Text(verbatim: prefix)
            + Text(verbatim: match).foregroundColor(.accentColor)
            + Text(verbatim: suffix)
    }

    private func statusRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    private func selectionBackground(for result: CodeUsageResult) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                result.id == viewModel.selectedResultID
                    ? Color.accentColor.opacity(0.18)
                    : (result.isInTestDirectory ? Color.green.opacity(0.18) : Color.clear)
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    private var keyMonitor: some View {
        CodeUsageKeyMonitor(
            onEscape: {
                viewModel.dismiss()
            },
            onReturn: {
                guard let result = viewModel.selectedResult else { return }
                open(result)
            },
            onMoveSelection: { offset in
                if offset > 0 {
                    viewModel.selectNextResult()
                } else {
                    viewModel.selectPreviousResult()
                }
            }
        )
    }

    private func open(_ result: CodeUsageResult) {
        viewModel.dismiss()
        openResult(result)
    }
}

private struct CodeUsageKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void
    let onReturn: () -> Void
    let onMoveSelection: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onEscape: onEscape,
            onReturn: onReturn,
            onMoveSelection: onMoveSelection
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
        context.coordinator.onReturn = onReturn
        context.coordinator.onMoveSelection = onMoveSelection
        context.coordinator.captureFocus(in: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove(restoringFocusFrom: nsView)
    }

    private final class KeyCaptureView: NSView {
        weak var coordinator: Coordinator?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.captureFocus(in: self)
        }

        override func keyDown(with event: NSEvent) {
            coordinator?.handleFocusedKeyDown(event)
        }
    }

    final class Coordinator {
        var onEscape: () -> Void
        var onReturn: () -> Void
        var onMoveSelection: (Int) -> Void

        private var monitor: Any?
        private weak var captureView: NSView?
        private weak var previousFirstResponder: NSResponder?
        private var didCaptureFocus = false

        init(
            onEscape: @escaping () -> Void,
            onReturn: @escaping () -> Void,
            onMoveSelection: @escaping (Int) -> Void
        ) {
            self.onEscape = onEscape
            self.onReturn = onReturn
            self.onMoveSelection = onMoveSelection
        }

        deinit {
            remove(restoringFocusFrom: captureView)
        }

        func install(for view: NSView) {
            captureView = view
            captureFocus(in: view)
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleLocalKeyDown(event) ?? event
            }
        }

        func captureFocus(in view: NSView) {
            guard let window = view.window else { return }
            guard window.firstResponder !== view else { return }

            if !didCaptureFocus {
                previousFirstResponder = window.firstResponder
                didCaptureFocus = true
            }

            window.makeFirstResponder(view)
        }

        func remove(restoringFocusFrom view: NSView?) {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            restoreFocus(from: view)
        }

        func handleFocusedKeyDown(_ event: NSEvent) {
            _ = handle(event, allowsCommandPassthrough: false)
        }

        private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
            handle(event, allowsCommandPassthrough: true) ? nil : event
        }

        private func handle(_ event: NSEvent, allowsCommandPassthrough: Bool) -> Bool {
            let commandModifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard commandModifiers.isEmpty else {
                return !allowsCommandPassthrough
            }

            switch event.keyCode {
            case KeyCode.escape:
                onEscape()
                return true

            case KeyCode.returnKey, KeyCode.keypadEnter:
                onReturn()
                return true

            case KeyCode.downArrow:
                onMoveSelection(1)
                return true

            case KeyCode.upArrow:
                onMoveSelection(-1)
                return true

            default:
                return true
            }
        }

        private func restoreFocus(from view: NSView?) {
            defer {
                previousFirstResponder = nil
                didCaptureFocus = false
            }

            guard let view, let window = view.window else { return }
            guard window.firstResponder === view else { return }

            if let previousFirstResponder {
                window.makeFirstResponder(previousFirstResponder)
            } else {
                window.makeFirstResponder(nil)
            }
        }
    }
}

