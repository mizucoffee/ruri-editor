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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("ruri.textSearch.previewSplitFraction") private var previewSplitFraction = 0.45

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
                    .frame(height: showsResultList ? 560 : 360)
            }
        }
        .frame(width: 980)
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
            OverlayVerticalSplit(topFraction: $previewSplitFraction) {
                resultList
            } bottom: {
                TextSearchPreviewSection(
                    preview: viewModel.preview,
                    selectedResult: viewModel.selectedResult,
                    colorScheme: colorScheme
                )
            }
        }
    }

    private var showsResultList: Bool {
        !viewModel.isSearching && viewModel.errorMessage == nil && !viewModel.results.isEmpty
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
            .onChange(of: viewModel.selectionScrollRequest) { _, request in
                guard let request else { return }

                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(request.resultID, anchor: .center)
                }
            }
        }
    }

    private func resultRow(_ result: ProjectTextSearchResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            snippetText(for: result)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 16)

            Text(result.fileName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(result.lineNumber)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(selectionBackground(for: result))
        .simultaneousGesture(
            TapGesture().onEnded {
                viewModel.selectResult(result.id)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                open(result)
            }
        )
    }

    private func snippetText(for result: ProjectTextSearchResult) -> Text {
        Text(snippetAttributedString(for: result))
    }

    private func snippetAttributedString(for result: ProjectTextSearchResult) -> AttributedString {
        let line = trimmedSnippetLine(for: result)
        let string = line.text as String
        var attributed = AttributedString(string)

        if let syntaxRuns = viewModel.snippetSyntaxRuns[result.id], !syntaxRuns.isEmpty {
            let themeName = SyntaxHighlightingService.themeName(
                for: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            )

            for run in syntaxRuns {
                let shiftedRange = NSRange(
                    location: run.location - line.indentLength,
                    length: run.length
                ).clamped(toUTF16Length: line.text.length)
                guard shiftedRange.length > 0,
                      let stringRange = Range(shiftedRange, in: string),
                      let attributedRange = Range(stringRange, in: attributed) else {
                    continue
                }

                attributed[attributedRange].foregroundColor = Color(
                    nsColor: SyntaxHighlightPalette.color(for: run.role, themeName: themeName)
                )
            }
        }

        let matchRange = line.matchRange.clamped(toUTF16Length: line.text.length)
        if matchRange.length > 0,
           let stringRange = Range(matchRange, in: string),
           let attributedRange = Range(stringRange, in: attributed) {
            attributed[attributedRange].backgroundColor = Color(nsColor: .systemYellow)
                .opacity(colorScheme == .dark ? 0.30 : 0.36)
        }

        return attributed
    }

    private func trimmedSnippetLine(
        for result: ProjectTextSearchResult
    ) -> (text: NSString, matchRange: NSRange, indentLength: Int) {
        let line = result.lineText as NSString
        let matchRange = result.lineMatchRange.nsRange

        var indentLength = 0
        while indentLength < line.length {
            let character = line.character(at: indentLength)
            guard character == 0x20 || character == 0x09 else { break }
            indentLength += 1
        }

        guard indentLength > 0 else {
            return (line, matchRange, 0)
        }

        let trimmedText = line.substring(from: indentLength) as NSString
        guard matchRange.location >= indentLength else {
            return (trimmedText, NSRange(location: 0, length: 0), indentLength)
        }

        return (
            trimmedText,
            NSRange(location: matchRange.location - indentLength, length: matchRange.length),
            indentLength
        )
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

private struct TextSearchPreviewSection: View {
    @ObservedObject var preview: CodePreviewController
    let selectedResult: ProjectTextSearchResult?
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let selectedResult {
                Text(verbatim: "\(selectedResult.relativePath):\(selectedResult.lineNumber)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    @ViewBuilder
    private var content: some View {
        if let failure = preview.failure {
            status(failure == .fileTooLarge ? AppText.textSearchPreviewTooLarge : AppText.textSearchPreviewUnavailable)
        } else if let document = preview.document {
            CodePreviewPane(document: document, colorScheme: colorScheme)
                .overlay(alignment: .topTrailing) {
                    if preview.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                    }
                }
        } else {
            status(AppText.textSearchPreviewLoading, showsProgress: preview.isLoading)
        }
    }

    private func status(_ text: LocalizedStringKey, showsProgress: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
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

