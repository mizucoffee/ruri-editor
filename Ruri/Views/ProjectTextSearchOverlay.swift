//
//  ProjectTextSearchOverlay.swift
//  ruri
//

import AppKit
import SwiftUI

struct ProjectTextSearchOverlay: View {
    @ObservedObject var viewModel: ProjectTextSearchViewModel
    let openResult: (ProjectTextSearchResult) -> Void

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
            controls

            if shouldShowResultArea {
                Divider()

                resultArea
                    .frame(height: 360)
            }
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

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField(AppText.textSearchPlaceholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                filterField(
                    systemImage: "folder",
                    placeholder: AppText.textSearchDirectoryPlaceholder,
                    text: $viewModel.directoryPath
                )

                filterField(
                    systemImage: "line.3.horizontal.decrease.circle",
                    placeholder: AppText.textSearchFileMaskPlaceholder,
                    text: $viewModel.fileMask
                )
            }

            HStack(spacing: 18) {
                Toggle(isOn: $viewModel.usesRegularExpression) {
                    Label {
                        Text(AppText.textSearchRegexToggle)
                    } icon: {
                        Image(systemName: "curlybraces")
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $viewModel.isCaseSensitive) {
                    Label {
                        Text(AppText.textSearchCaseSensitiveToggle)
                    } icon: {
                        Image(systemName: "textformat")
                    }
                }
                .toggleStyle(.checkbox)

                Spacer(minLength: 0)

                if let summaryDescription = viewModel.summaryDescription {
                    Text(summaryDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func filterField(
        systemImage: String,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.70))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28))
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        if viewModel.isSearching {
            statusRow(AppText.textSearchSearching, showsProgress: true)
        } else if let errorMessage = viewModel.errorMessage {
            statusRow(LocalizedStringKey(errorMessage), showsProgress: false)
        } else if viewModel.hasQuery && viewModel.results.isEmpty {
            statusRow(AppText.textSearchNoResults, showsProgress: false)
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

    private func resultRow(_ result: ProjectTextSearchResult) -> some View {
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

    private func snippetText(for result: ProjectTextSearchResult) -> Text {
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

    private func statusRow(_ text: LocalizedStringKey, showsProgress: Bool) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
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

    private func selectionBackground(for result: ProjectTextSearchResult) -> some View {
        let fill: Color = result.id == viewModel.selectedResultID
            ? Color.accentColor.opacity(0.18)
            : (result.isInTestDirectory ? Color.green.opacity(0.18) : Color.clear)

        return RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    private var shouldShowResultArea: Bool {
        viewModel.isSearching || viewModel.hasQuery || viewModel.errorMessage != nil
    }

    private var keyMonitor: some View {
        ProjectTextSearchKeyMonitor(
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

    private func open(_ result: ProjectTextSearchResult) {
        viewModel.dismiss()
        openResult(result)
    }
}

private struct ProjectTextSearchKeyMonitor: NSViewRepresentable {
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

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

private extension NSRange {
    func clamped(toUTF16Length length: Int) -> NSRange {
        guard location != NSNotFound else {
            return NSRange(location: length, length: 0)
        }

        let clampedLocation = min(max(0, location), length)
        let maximumLength = max(0, length - clampedLocation)
        return NSRange(location: clampedLocation, length: min(max(0, self.length), maximumLength))
    }
}
