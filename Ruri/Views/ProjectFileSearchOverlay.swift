//
//  ProjectFileSearchOverlay.swift
//  ruri
//

import AppKit
import SwiftUI

struct ProjectFileSearchOverlay: View {
    @ObservedObject var viewModel: ProjectFileSearchViewModel
    let openFile: (URL) -> Void

    @FocusState private var isSearchFocused: Bool

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
                .onAppear {
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: viewModel.isPresented)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            searchField

            if shouldShowResultArea {
                Divider()

                resultArea
                    .frame(maxHeight: 320)
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
        }
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField(AppText.fileSearchPlaceholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var resultArea: some View {
        if viewModel.isIndexing {
            statusRow(AppText.fileSearchIndexing)
        } else if let errorMessage = viewModel.errorMessage {
            statusRow(LocalizedStringKey(errorMessage))
        } else if viewModel.hasQuery && viewModel.results.isEmpty {
            statusRow(AppText.fileSearchNoResults)
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

    private func resultRow(_ result: ProjectFileSearchEntry) -> some View {
        Button {
            open(result)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.fileName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(result.displayParentPath)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .contentShape(Rectangle())
            .background(selectionBackground(for: result))
        }
        .buttonStyle(.plain)
    }

    private func statusRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            if viewModel.isIndexing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    private func selectionBackground(for result: ProjectFileSearchEntry) -> some View {
        let fill: Color = result.id == viewModel.selectedResultID
            ? Color.accentColor.opacity(0.18)
            : (result.isInTestDirectory ? Color.green.opacity(0.18) : Color.clear)

        return RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    private var shouldShowResultArea: Bool {
        viewModel.isIndexing || viewModel.hasQuery || viewModel.errorMessage != nil
    }

    private var keyMonitor: some View {
        ProjectFileSearchKeyMonitor(
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
        .frame(width: 0, height: 0)
    }

    private func open(_ result: ProjectFileSearchEntry) {
        viewModel.dismiss()
        openFile(result.url)
    }
}

private struct ProjectFileSearchKeyMonitor: NSViewRepresentable {
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
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
        context.coordinator.onReturn = onReturn
        context.coordinator.onMoveSelection = onMoveSelection
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onEscape: () -> Void
        var onReturn: () -> Void
        var onMoveSelection: (Int) -> Void

        private var monitor: Any?

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
            guard !Self.hasMarkedText() else { return event }

            let commandModifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard commandModifiers.isEmpty else { return event }

            switch event.keyCode {
            case KeyCode.escape:
                onEscape()
                return nil

            case KeyCode.returnKey, KeyCode.keypadEnter:
                onReturn()
                return nil

            case KeyCode.downArrow:
                onMoveSelection(1)
                return nil

            case KeyCode.upArrow:
                onMoveSelection(-1)
                return nil

            default:
                return event
            }
        }

        private static func hasMarkedText() -> Bool {
            guard let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient else {
                return false
            }

            return inputClient.hasMarkedText()
        }
    }
}

struct DoubleShiftKeyDetector: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.action = action
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var action: () -> Void

        private var monitor: Any?
        private var keySequence = DoubleShiftKeySequence()

        init(action: @escaping () -> Void) {
            self.action = action
        }

        deinit {
            remove()
        }

        func install() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func remove() {
            guard let monitor else { return }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func handle(_ event: NSEvent) {
            switch event.type {
            case .flagsChanged:
                handleFlagsChanged(event)
            case .keyDown:
                keySequence.cancelPendingShift()
            default:
                break
            }
        }

        private func handleFlagsChanged(_ event: NSEvent) {
            guard Self.isShiftKey(event.keyCode) else {
                keySequence.cancelPendingShift()
                return
            }

            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift) else {
                return
            }

            if keySequence.registerShiftDown(at: event.timestamp) {
                action()
            }
        }

        private static func isShiftKey(_ keyCode: UInt16) -> Bool {
            keyCode == KeyCode.leftShift || keyCode == KeyCode.rightShift
        }
    }
}

struct DoubleShiftKeySequence {
    private let maximumInterval: TimeInterval
    private var lastShiftDownTimestamp: TimeInterval?

    init(maximumInterval: TimeInterval = 0.5) {
        self.maximumInterval = maximumInterval
    }

    mutating func registerShiftDown(at timestamp: TimeInterval) -> Bool {
        guard let lastShiftDownTimestamp else {
            self.lastShiftDownTimestamp = timestamp
            return false
        }

        if timestamp - lastShiftDownTimestamp <= maximumInterval {
            self.lastShiftDownTimestamp = nil
            return true
        }

        self.lastShiftDownTimestamp = timestamp
        return false
    }

    mutating func cancelPendingShift() {
        lastShiftDownTimestamp = nil
    }
}

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
