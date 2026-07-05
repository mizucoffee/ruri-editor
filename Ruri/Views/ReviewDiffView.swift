//
//  ReviewDiffView.swift
//  ruri
//

import AppKit
import SwiftUI

// MARK: - Review Diff Root View

struct ReviewDiffView: View {
    let showsFocusLine: Bool
    let state: ReviewDiffState
    let selectedBase: GitReviewDiffBase?
    let localBranches: [GitLocalBranchInfo]
    let remoteBranches: [GitRemoteBranchInfo]
    let isLoadingRemoteBranches: Bool
    let remoteBranchErrorMessage: String?
    let hideWhitespace: Bool
    let viewedFilePaths: Set<String>
    let viewedStateSyncsToPullRequest: Bool
    @Binding var displayMode: ReviewDiffDisplayMode
    @Binding var wrapLines: Bool
    let selectBase: (GitReviewDiffBase) -> Void
    let loadRemoteBranches: (Bool) -> Void
    let refresh: () -> Void
    let setHideWhitespace: (Bool) -> Void
    let setFileViewed: (String, Bool) -> Void
    let openFile: (URL) -> Void
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .overlay(alignment: .top) {
                    if showsFocusLine {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: EditorMetrics.focusLineHeight)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: showsFocusLine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("File changes", systemImage: "doc.text.magnifyingglass")
                .font(.headline)

            if let snapshot {
                ReviewDiffBasePicker(
                    selectedBase: selectedBase,
                    localBranches: localBranches,
                    remoteBranches: remoteBranches,
                    isLoadingRemoteBranches: isLoadingRemoteBranches,
                    remoteBranchErrorMessage: remoteBranchErrorMessage,
                    directionDisplayName: "\(snapshot.targetBranch.displayName) -> \(snapshot.baseDisplayName)",
                    selectBase: selectBase,
                    loadRemoteBranches: loadRemoteBranches
                )

                Spacer()

                Text("\(snapshot.files.count) files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(viewedFileCount(in: snapshot)) / \(snapshot.files.count) viewed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ReviewDiffSummary(additions: snapshot.totalAdditions, deletions: snapshot.totalDeletions)
            } else {
                Spacer()

                ReviewDiffBasePicker(
                    selectedBase: selectedBase,
                    localBranches: localBranches,
                    remoteBranches: remoteBranches,
                    isLoadingRemoteBranches: isLoadingRemoteBranches,
                    remoteBranchErrorMessage: remoteBranchErrorMessage,
                    directionDisplayName: nil,
                    selectBase: selectBase,
                    loadRemoteBranches: loadRemoteBranches
                )
            }

            diffDisplayPicker
            wrapLinesToggle
            hideWhitespaceToggle

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .help("Refresh diff")
            .accessibilityLabel("Refresh diff")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var diffDisplayPicker: some View {
        Picker(
            "Diff display",
            selection: $displayMode
        ) {
            ForEach(ReviewDiffDisplayMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 196, height: 24)
        .fixedSize()
        .help("Diff display")
        .accessibilityLabel("Diff display")
    }

    private var wrapLinesToggle: some View {
        Toggle("Wrap", isOn: $wrapLines)
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .fixedSize()
            .disabled(displayMode == .sideBySide)
            .help("Wrap diff lines")
            .accessibilityLabel("Wrap diff lines")
    }

    private var hideWhitespaceToggle: some View {
        Toggle(
            "Hide whitespace",
            isOn: Binding(
                get: { hideWhitespace },
                set: { setHideWhitespace($0) }
            )
        )
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .fixedSize()
        .help("Hide whitespace differences")
        .accessibilityLabel("Hide whitespace")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .unavailable:
            ReviewDiffMessageView(
                systemImage: "square.slash",
                title: "Review unavailable",
                message: "Open a Git repository on a branch to use Review mode."
            )

        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading review diff")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            ReviewDiffMessageView(
                systemImage: "exclamationmark.triangle",
                title: "Could not load diff",
                message: message,
                refresh: refresh
            )

        case .loaded(let snapshot):
            if snapshot.files.isEmpty {
                ReviewDiffMessageView(
                    systemImage: "checkmark.circle",
                    title: "No changes",
                    message: "There are no changes from \(snapshot.baseDisplayName)."
                )
            } else {
                ScrollView {
                    // 非lazyのVStackで全行を実体化し、総コンテンツ高を常に正確に保つ
                    // (LazyVStackは未実体化行の高さを平均で推定するためスクロールバーが飛ぶ)。
                    // 行高固定で高さは事前計算できるため各行は軽く、NSScrollViewを持つ
                    // 重いペインだけを ReviewDiffFileView がビューポート近傍で生成する。
                    // 全ペイン即時実体化はウィンドウ内のスクロールビュー数が数百〜数千に達し
                    // AppKitのレイアウト/追跡登録がハングするため必ず避けること。
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(snapshot.files.enumerated()), id: \.element.id) { index, file in
                            let isViewed = viewedFilePaths.contains(file.displayRelativePath)
                            ReviewDiffFileView(
                                file: file,
                                targetWorktreeRootURL: snapshot.targetWorktreeRootURL,
                                displayMode: displayMode,
                                wrapLines: wrapLines,
                                isViewed: isViewed,
                                initiallyExpanded: ReviewDiffExpansionPolicy.initiallyExpanded(
                                    isViewed: isViewed,
                                    lineCount: file.diff.hunks.reduce(0) { $0 + $1.lines.count },
                                    fileIndex: index
                                ),
                                viewedStateSyncsToPullRequest: viewedStateSyncsToPullRequest,
                                setViewed: { setFileViewed(file.displayRelativePath, $0) },
                                openFile: openFile,
                                requestCodeNavigation: requestCodeNavigation,
                                codeNavigationHoverRange: codeNavigationHoverRange
                            )
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var snapshot: GitReviewDiffSnapshot? {
        guard case .loaded(let snapshot) = state else { return nil }
        return snapshot
    }

    private var isLoading: Bool {
        guard case .loading = state else { return false }
        return true
    }

    private func viewedFileCount(in snapshot: GitReviewDiffSnapshot) -> Int {
        snapshot.files.filter { viewedFilePaths.contains($0.displayRelativePath) }.count
    }
}

// MARK: - Display Mode

enum ReviewDiffDisplayMode: String, CaseIterable, Identifiable {
    case unified
    case sideBySide

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .unified:
            "Unified"
        case .sideBySide:
            "Side by side"
        }
    }
}

// MARK: - Base Picker

private struct ReviewDiffBasePicker: View {
    let selectedBase: GitReviewDiffBase?
    let localBranches: [GitLocalBranchInfo]
    let remoteBranches: [GitRemoteBranchInfo]
    let isLoadingRemoteBranches: Bool
    let remoteBranchErrorMessage: String?
    let directionDisplayName: String?
    let selectBase: (GitReviewDiffBase) -> Void
    let loadRemoteBranches: (Bool) -> Void

    @State private var isPresented = false
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLocalBranches: [GitLocalBranchInfo] {
        let selectableBranches = localBranches.filter { branch in
            !isRuriBaseBranch(branch)
        }
        guard !trimmedSearchText.isEmpty else { return selectableBranches }
        return selectableBranches.filter { branch in
            branch.name.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var ruriBaseLocalBranch: GitLocalBranchInfo? {
        localBranches.first(where: isRuriBaseBranch)
    }

    private var filteredRemoteBranches: [GitRemoteBranchInfo] {
        guard !trimmedSearchText.isEmpty else { return remoteBranches }
        return remoteBranches.filter { branch in
            branch.fullName.localizedCaseInsensitiveContains(trimmedSearchText)
                || branch.branchName.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    var body: some View {
        Button {
            isPresented.toggle()
            if isPresented && remoteBranches.isEmpty && !isLoadingRemoteBranches {
                loadRemoteBranches(true)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(directionDisplayName ?? "Base: \(selectedBase?.displayName ?? "Default")")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: directionDisplayName == nil ? 260 : 320)
        .help("Review diff base")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Review Base")
                    .font(.headline)
                Spacer()
                Button {
                    loadRemoteBranches(true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoadingRemoteBranches)
                .help("Refresh remote branches")
            }

            TextField("Search branches", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List {
                if let ruriBaseLocalBranch {
                    Button {
                        select(.branch(ruriBaseLocalBranch.name))
                    } label: {
                        ReviewDiffBaseRow(
                            title: ruriBaseLocalBranch.name,
                            subtitle: "ruri-base branch",
                            systemImage: "arrow.triangle.branch.fill",
                            isSelected: selectedBase == .branch(ruriBaseLocalBranch.name)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    select(.uncommitted)
                } label: {
                    ReviewDiffBaseRow(
                        title: GitReviewDiffBase.uncommitted.displayName,
                        subtitle: "Current branch working tree",
                        systemImage: "pencil",
                        isSelected: selectedBase == .uncommitted
                    )
                }
                .buttonStyle(.plain)

                if !filteredLocalBranches.isEmpty {
                    Section("Local") {
                        ForEach(filteredLocalBranches) { branch in
                            Button {
                                select(.branch(branch.name))
                            } label: {
                                ReviewDiffBaseRow(
                                    title: branch.name,
                                    subtitle: "Local branch",
                                    systemImage: "arrow.triangle.branch",
                                    isSelected: selectedBase == .branch(branch.name)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !filteredRemoteBranches.isEmpty {
                    Section("Remote") {
                        ForEach(filteredRemoteBranches) { branch in
                            Button {
                                select(.branch(branch.fullName))
                            } label: {
                                ReviewDiffBaseRow(
                                    title: branch.fullName,
                                    subtitle: branch.remoteName,
                                    systemImage: "icloud.and.arrow.down",
                                    isSelected: selectedBase == .branch(branch.fullName)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 360, height: 280)

            footer
        }
        .padding(14)
        .frame(width: 388)
    }

    @ViewBuilder
    private var footer: some View {
        if isLoadingRemoteBranches {
            ProgressView("Fetching remote branches")
                .controlSize(.small)
        } else if let remoteBranchErrorMessage,
                  !remoteBranchErrorMessage.isEmpty,
                  remoteBranches.isEmpty {
            HStack(spacing: 8) {
                Text(remoteBranchErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("Retry") {
                    loadRemoteBranches(true)
                }
            }
        } else if filteredLocalBranches.isEmpty && filteredRemoteBranches.isEmpty && selectedBase != .uncommitted {
            Text("No matching branches")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ base: GitReviewDiffBase) {
        selectBase(base)
        isPresented = false
    }

    private func isRuriBaseBranch(_ branch: GitLocalBranchInfo) -> Bool {
        branch.checkedOutWorktreeURL?.lastPathComponent == "ruri-base"
    }
}

// MARK: - Base Row, Summary & Messages

private struct ReviewDiffBaseRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ReviewDiffSummary: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("+\(additions)")
                .foregroundStyle(.green)
            Text("-\(deletions)")
                .foregroundStyle(.red)
        }
        .font(.subheadline.monospacedDigit())
    }
}

private struct ReviewDiffMessageView: View {
    let systemImage: String
    let title: String
    let message: String
    var refresh: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let refresh {
                Button {
                    refresh()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File View

private struct ReviewDiffFileView: View {
    let file: GitReviewFileDiff
    let targetWorktreeRootURL: URL
    let displayMode: ReviewDiffDisplayMode
    let wrapLines: Bool
    let isViewed: Bool
    let viewedStateSyncsToPullRequest: Bool
    let setViewed: (Bool) -> Void
    let openFile: (URL) -> Void
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool
    @State private var syntaxHighlights = ReviewDiffSyntaxHighlights.empty
    @State private var didCopyPath = false
    @State private var isNearViewport = false

    init(
        file: GitReviewFileDiff,
        targetWorktreeRootURL: URL,
        displayMode: ReviewDiffDisplayMode,
        wrapLines: Bool,
        isViewed: Bool,
        initiallyExpanded: Bool,
        viewedStateSyncsToPullRequest: Bool,
        setViewed: @escaping (Bool) -> Void,
        openFile: @escaping (URL) -> Void,
        requestCodeNavigation: @escaping (ReviewDiffCodeNavigationRequest) -> Void,
        codeNavigationHoverRange: @escaping (ReviewDiffCodeNavigationRequest) async -> NSRange?
    ) {
        self.file = file
        self.targetWorktreeRootURL = targetWorktreeRootURL
        self.displayMode = displayMode
        self.wrapLines = wrapLines
        self.isViewed = isViewed
        self.viewedStateSyncsToPullRequest = viewedStateSyncsToPullRequest
        self.setViewed = setViewed
        self.openFile = openFile
        self.requestCodeNavigation = requestCodeNavigation
        self.codeNavigationHoverRange = codeNavigationHoverRange
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let currentSyntaxHighlightRequestID = syntaxHighlightRequestID
        let currentSyntaxHighlights = syntaxHighlights.matching(requestID: currentSyntaxHighlightRequestID)

        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider()

                if file.isBinary && file.diff.hunks.isEmpty {
                    noPreviewRow("Binary file not shown")
                } else if file.diff.hunks.isEmpty {
                    noPreviewRow("No text diff")
                } else {
                    ReviewDiffFileContentView(
                        file: file,
                        oldFileURL: oldFileURL,
                        newFileURL: newFileURL,
                        displayMode: displayMode,
                        wrapLines: wrapLines,
                        isNearViewport: isNearViewport,
                        syntaxHighlights: currentSyntaxHighlights,
                        requestCodeNavigation: requestCodeNavigation,
                        codeNavigationHoverRange: codeNavigationHoverRange
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
        .background {
            // onGeometryChange + .scrollView 座標系は macOS では NSScrollView の
            // スクロールで再評価されず判定が凍結するため、AppKit の clip bounds
            // 通知を購読するセンサーで可視近傍を検出する。
            ReviewDiffVisibilitySensor { newValue in
                isNearViewport = newValue
            }
        }
        .task(id: syntaxHighlightRequestID) {
            syntaxHighlights = .empty
            guard isExpanded, isNearViewport else {
                return
            }

            let highlights = await ReviewDiffSyntaxHighlighter.highlights(
                for: file,
                requestID: currentSyntaxHighlightRequestID,
                colorScheme: colorScheme
            )
            guard !Task.isCancelled else { return }
            syntaxHighlights = highlights
        }
        .onChange(of: isViewed) { _, newValue in
            isExpanded = !newValue
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide diff" : "Show diff")
            .accessibilityLabel(isExpanded ? "Hide diff" : "Show diff")

            ReviewDiffStatusBadge(status: file.status)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let newFileURL {
                        Button {
                            openFile(newFileURL)
                        } label: {
                            Text(file.displayRelativePath)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .help("Open file")
                        .accessibilityLabel("Open \(file.displayRelativePath)")
                    } else {
                        Text(file.displayRelativePath)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    copyPathButton
                }

                if let oldPath = file.oldRelativePath,
                   let newPath = file.newRelativePath,
                   oldPath != newPath {
                    Text(oldPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            ReviewDiffSummary(additions: file.additions, deletions: file.deletions)

            viewedButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var copyPathButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.displayRelativePath, forType: .string)
            didCopyPath = true
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                didCopyPath = false
            }
        } label: {
            Image(systemName: didCopyPath ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(didCopyPath ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AppText.copyFilePathCommand)
        .accessibilityLabel("Copy file path")
    }

    private var viewedButton: some View {
        Toggle(
            "Viewed",
            isOn: Binding(
                get: { isViewed },
                set: { setViewed($0) }
            )
        )
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Color(nsColor: isViewed ? .windowBackgroundColor : .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
        .help(viewedButtonHelp)
        .accessibilityLabel("Mark \(file.displayRelativePath) as viewed")
    }

    private var viewedButtonHelp: String {
        let action = isViewed ? "Mark as not viewed" : "Mark as viewed"
        return viewedStateSyncsToPullRequest ? "\(action) (synced with the pull request)" : action
    }

    private func noPreviewRow(_ message: String) -> some View {
        Label(message, systemImage: "doc")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syntaxHighlightRequestID: Int {
        var hasher = Hasher()
        hasher.combine(file.id)
        hasher.combine(file.isBinary)
        hasher.combine(isExpanded)
        hasher.combine(isNearViewport)
        hasher.combine(colorScheme == .dark)
        for hunk in file.diff.hunks {
            hasher.combine(hunk.oldStart)
            hasher.combine(hunk.newStart)
            for line in hunk.lines {
                hasher.combine(line.kind.syntaxHashValue)
                hasher.combine(line.oldLineNumber)
                hasher.combine(line.newLineNumber)
                hasher.combine(line.content)
            }
        }
        return hasher.finalize()
    }

    private var oldFileURL: URL? {
        guard let oldRelativePath = file.oldRelativePath else { return nil }
        return targetWorktreeRootURL.appending(path: oldRelativePath).standardizedFileURL
    }

    private var newFileURL: URL? {
        guard let newRelativePath = file.newRelativePath else { return nil }
        return targetWorktreeRootURL.appending(path: newRelativePath).standardizedFileURL
    }
}

// MARK: - Status Badge

private struct ReviewDiffStatusBadge: View {
    let status: GitFileDisplayStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.bold().monospaced())
            .foregroundStyle(color)
            .frame(width: 24, height: 20)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .help(status.description)
    }

    private var color: Color {
        switch status {
        case .added, .untracked:
            .green
        case .deleted:
            .red
        case .renamed, .copied:
            .blue
        case .conflicted:
            .orange
        case .modified:
            .secondary
        }
    }
}

// MARK: - Syntax Highlighting

private enum ReviewDiffSyntaxHighlighter {
    static func highlights(
        for file: GitReviewFileDiff,
        requestID: Int,
        colorScheme: ColorScheme
    ) async -> ReviewDiffSyntaxHighlights {
        guard !file.isBinary,
              !file.diff.hunks.isEmpty else {
            return .empty
        }

        let oldLanguageName = languageName(for: file.oldRelativePath) ?? languageName(for: file.newRelativePath)
        let newLanguageName = languageName(for: file.newRelativePath) ?? oldLanguageName
        guard oldLanguageName != nil || newLanguageName != nil else {
            return .empty
        }

        let oldDocument = syntaxDocument(
            for: file.diff.hunks,
            side: .old
        )
        let newDocument = syntaxDocument(
            for: file.diff.hunks,
            side: .new
        )
        let service = SyntaxHighlightingService()
        let oldRuns = await service.highlightedRuns(for: oldDocument.text, languageName: oldLanguageName)
        let newRuns = await service.highlightedRuns(for: newDocument.text, languageName: newLanguageName)
        let themeName = colorScheme == .dark ? "tree-sitter-dark" : "tree-sitter-light"

        var linesByKey: [ReviewDiffLineKey: ReviewDiffSyntaxLine] = [:]
        linesByKey.merge(syntaxLines(for: oldDocument, runs: oldRuns)) { current, _ in current }
        linesByKey.merge(syntaxLines(for: newDocument, runs: newRuns)) { current, _ in current }

        return ReviewDiffSyntaxHighlights(
            requestID: requestID,
            linesByKey: linesByKey,
            themeName: themeName
        )
    }

    private static func languageName(for relativePath: String?) -> String? {
        guard let relativePath,
              !relativePath.isEmpty else { return nil }
        return SyntaxLanguageResolver.languageName(for: URL(filePath: relativePath))
    }

    private static func syntaxDocument(
        for hunks: [SourceDiffHunk],
        side: ReviewDiffSyntaxSide
    ) -> ReviewDiffSyntaxDocument {
        var text = ""
        var lines: [ReviewDiffSyntaxDocument.Line] = []

        for (hunkIndex, hunk) in hunks.enumerated() {
            for (lineIndex, line) in hunk.lines.enumerated() where includes(line.kind, in: side) {
                let start = text.utf16.count
                text += line.content
                lines.append(ReviewDiffSyntaxDocument.Line(
                    key: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: side),
                    content: line.content,
                    startUTF16Offset: start
                ))
                text += "\n"
            }
        }

        return ReviewDiffSyntaxDocument(text: text, lines: lines)
    }

    private static func includes(_ kind: SourceDiffLine.Kind, in side: ReviewDiffSyntaxSide) -> Bool {
        switch (kind, side) {
        case (.context, _), (.deletion, .old), (.addition, .new):
            return true
        case (.deletion, .new), (.addition, .old):
            return false
        }
    }

    private static func syntaxLines(
        for document: ReviewDiffSyntaxDocument,
        runs: [SyntaxHighlightRun]
    ) -> [ReviewDiffLineKey: ReviewDiffSyntaxLine] {
        var linesByKey: [ReviewDiffLineKey: ReviewDiffSyntaxLine] = [:]

        for line in document.lines {
            let lineLength = line.content.utf16.count
            let lineRange = NSRange(location: line.startUTF16Offset, length: lineLength)
            let lineRuns = runs.compactMap { run -> (range: NSRange, role: SyntaxHighlightRole)? in
                guard let intersection = intersection(run.range, lineRange),
                      intersection.length > 0 else {
                    return nil
                }
                return (
                    NSRange(location: intersection.location - line.startUTF16Offset, length: intersection.length),
                    run.role
                )
            }

            linesByKey[line.key] = ReviewDiffSyntaxLine(
                segments: segments(for: line.content, runs: lineRuns)
            )
        }

        return linesByKey
    }

    private static func intersection(_ lhs: NSRange, _ rhs: NSRange) -> NSRange? {
        let lowerBound = max(lhs.location, rhs.location)
        let upperBound = min(NSMaxRange(lhs), NSMaxRange(rhs))
        guard lowerBound < upperBound else { return nil }
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private static func segments(
        for content: String,
        runs: [(range: NSRange, role: SyntaxHighlightRole)]
    ) -> [ReviewDiffSyntaxSegment] {
        let displayText = content.isEmpty ? " " : content
        guard !runs.isEmpty else {
            return [ReviewDiffSyntaxSegment(text: displayText, role: nil)]
        }

        var segments: [ReviewDiffSyntaxSegment] = []
        var cursor = 0
        let sortedRuns = runs.sorted { lhs, rhs in
            lhs.range.location < rhs.range.location
        }
        let displayLength = displayText.utf16.count

        for run in sortedRuns {
            let start = max(cursor, min(run.range.location, displayLength))
            let end = max(start, min(NSMaxRange(run.range), displayLength))
            if cursor < start {
                appendSegment(
                    from: displayText,
                    range: NSRange(location: cursor, length: start - cursor),
                    role: nil,
                    to: &segments
                )
            }
            if start < end {
                appendSegment(
                    from: displayText,
                    range: NSRange(location: start, length: end - start),
                    role: run.role,
                    to: &segments
                )
            }
            cursor = max(cursor, end)
        }

        if cursor < displayLength {
            appendSegment(
                from: displayText,
                range: NSRange(location: cursor, length: displayLength - cursor),
                role: nil,
                to: &segments
            )
        }

        return segments.isEmpty ? [ReviewDiffSyntaxSegment(text: displayText, role: nil)] : segments
    }

    private static func appendSegment(
        from text: String,
        range: NSRange,
        role: SyntaxHighlightRole?,
        to segments: inout [ReviewDiffSyntaxSegment]
    ) {
        guard range.length > 0,
              let stringRange = Range(range, in: text) else {
            return
        }

        segments.append(ReviewDiffSyntaxSegment(text: String(text[stringRange]), role: role))
    }
}

// MARK: - Syntax Document Model

private struct ReviewDiffSyntaxDocument: Sendable {
    struct Line: Sendable {
        let key: ReviewDiffLineKey
        let content: String
        let startUTF16Offset: Int
    }

    let text: String
    let lines: [Line]
}

private extension SourceDiffLine.Kind {
    var syntaxHashValue: String {
        switch self {
        case .context:
            "context"
        case .addition:
            "addition"
        case .deletion:
            "deletion"
        }
    }
}

// MARK: - Layout Metrics

enum ReviewDiffLayout {
    static let minimumContentWidth: CGFloat = 760

    /// 1ペイン(NSTextView)あたりの最大行数。レイヤーバックのビューは
    /// Retina(2x)でおよそ8,000pt(Metalテクスチャ上限16384px)を超えた部分の
    /// 描画が破棄されるため、長いファイルはこの行数ごとにペインを分割して
    /// 積み上げる。256行 × 約20pt ≈ 5,100pt で上限に対して十分な余裕を持つ。
    static let maxLinesPerPane = 256
    static let codeFontSize: CGFloat = 12
    static let lineNumberWidth: CGFloat = 52
    static let lineNumberTrailingPadding: CGFloat = 8
    static let markerWidth: CGFloat = 22
    static let rowTrailingPadding: CGFloat = 14
    static let measuredWidthPadding: CGFloat = 8
    static let textContainerInset = NSSize(width: 8, height: 6)

    static var codeLineHeight: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        return ceil(font.ascender - font.descender + font.leading) + 4
    }

    static var lineNumberColumnWidth: CGFloat {
        lineNumberWidth + lineNumberTrailingPadding
    }

    static var unifiedCodePrefixWidth: CGFloat {
        lineNumberColumnWidth * 2 + markerWidth + rowTrailingPadding
    }

    static var sideBySideCodePrefixWidth: CGFloat {
        lineNumberColumnWidth + markerWidth + rowTrailingPadding
    }

    static func codeWidth(for content: String) -> CGFloat {
        let text = content.isEmpty ? " " : content
        let font = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + measuredWidthPadding
    }

    static func maxCodeWidth(in lines: [SourceDiffLine]) -> CGFloat {
        lines.map { codeWidth(for: $0.content) }.max() ?? codeWidth(for: "")
    }
}

// MARK: - File Content View

private struct ReviewDiffFileContentView: View {
    let file: GitReviewFileDiff
    let oldFileURL: URL?
    let newFileURL: URL?
    let displayMode: ReviewDiffDisplayMode
    let wrapLines: Bool
    let isNearViewport: Bool
    let syntaxHighlights: ReviewDiffSyntaxHighlights
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?
    @State private var horizontalSync = ReviewDiffFileHorizontalSyncGroups()

    var body: some View {
        switch displayMode {
        case .unified:
            if !isNearViewport {
                // オフスクリーンではドキュメント構築もNSScrollView生成もせず、
                // 実体化後と同一高さの空プレースホルダだけを置く(スクロールバー安定のため
                // 高さは行数から厳密に一致させる)。
                panePlaceholder(totalLineCount: ReviewDiffRenderedDocument.unifiedLineCount(for: file))
            } else {
                let documents = ReviewDiffRenderedDocument.unifiedDocuments(
                    for: file,
                    oldFileURL: oldFileURL,
                    newFileURL: newFileURL,
                    maxLinesPerDocument: ReviewDiffLayout.maxLinesPerPane
                )
                let fileCodeWidth = documents.map(\.maximumCodeWidth).max() ?? 0
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(documents.indices, id: \.self) { index in
                        ReviewDiffChunkedTextPane(
                            document: documents[index],
                            minimumCodeWidth: fileCodeWidth,
                            syntaxHighlights: syntaxHighlights,
                            wrapLines: wrapLines,
                            horizontalSync: wrapLines ? nil : horizontalSync.unified,
                            requestCodeNavigation: requestCodeNavigation,
                            codeNavigationHoverRange: codeNavigationHoverRange
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .sideBySide:
            if !isNearViewport {
                // old/new はペア化により常に同一行数のため、片側の行数で高さが確定する。
                panePlaceholder(totalLineCount: ReviewDiffRenderedDocument.sideBySideLineCount(for: file))
            } else {
                let oldDocuments = ReviewDiffRenderedDocument.sideBySideDocuments(
                    for: file,
                    side: .old,
                    fileURL: oldFileURL,
                    maxLinesPerDocument: ReviewDiffLayout.maxLinesPerPane
                )
                let newDocuments = ReviewDiffRenderedDocument.sideBySideDocuments(
                    for: file,
                    side: .new,
                    fileURL: newFileURL,
                    maxLinesPerDocument: ReviewDiffLayout.maxLinesPerPane
                )
                let oldCodeWidth = oldDocuments.map(\.maximumCodeWidth).max() ?? 0
                let newCodeWidth = newDocuments.map(\.maximumCodeWidth).max() ?? 0
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(oldDocuments.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 0) {
                            ReviewDiffChunkedTextPane(
                                document: oldDocuments[index],
                                minimumCodeWidth: oldCodeWidth,
                                syntaxHighlights: syntaxHighlights,
                                wrapLines: false,
                                horizontalSync: horizontalSync.old,
                                requestCodeNavigation: requestCodeNavigation,
                                codeNavigationHoverRange: codeNavigationHoverRange
                            )

                            Divider()

                            ReviewDiffChunkedTextPane(
                                document: newDocuments[index],
                                minimumCodeWidth: newCodeWidth,
                                syntaxHighlights: syntaxHighlights,
                                wrapLines: false,
                                horizontalSync: horizontalSync.new,
                                requestCodeNavigation: requestCodeNavigation,
                                codeNavigationHoverRange: codeNavigationHoverRange
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func panePlaceholder(totalLineCount: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: ReviewDiffScrollLayout.estimatedChunkedDocumentHeight(
                totalLineCount: totalLineCount,
                maxLinesPerDocument: ReviewDiffLayout.maxLinesPerPane,
                lineHeight: ReviewDiffLayout.codeLineHeight,
                textInsetHeight: ReviewDiffLayout.textContainerInset.height
            ))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chunked Text Pane

/// 1チャンク分のペイン。チャンク単位でもビューポート近傍判定を行い、
/// 範囲外は同一高さのプレースホルダに置き換える(巨大ファイルでも
/// 実体化されるNSScrollView/NSTextViewを可視近傍分に抑える)。
private struct ReviewDiffChunkedTextPane: View {
    let document: ReviewDiffRenderedDocument
    let minimumCodeWidth: CGFloat
    let syntaxHighlights: ReviewDiffSyntaxHighlights
    let wrapLines: Bool
    let horizontalSync: ReviewDiffPaneHorizontalSync?
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?
    @State private var isNearViewport = false

    var body: some View {
        Group {
            if isNearViewport {
                ReviewDiffTextPane(
                    document: document,
                    minimumCodeWidth: minimumCodeWidth,
                    syntaxHighlights: syntaxHighlights,
                    wrapLines: wrapLines,
                    horizontalSync: horizontalSync,
                    requestCodeNavigation: requestCodeNavigation,
                    codeNavigationHoverRange: codeNavigationHoverRange
                )
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: ReviewDiffScrollLayout.estimatedDocumentHeight(
            lineCount: document.lineCount,
            lineHeight: ReviewDiffLayout.codeLineHeight,
            textInsetHeight: ReviewDiffLayout.textContainerInset.height
        ))
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ReviewDiffVisibilitySensor { newValue in
                isNearViewport = newValue
            }
        }
    }
}

// MARK: - Visibility Sensor

/// 外側スクロールビューの clip bounds 変更(=スクロール)を購読し、
/// 自身がビューポートの前後1画面以内に入っているかを通知する透明ビュー。
/// SwiftUI の onGeometryChange は macOS では NSScrollView のスクロールで
/// 再評価されないため、可視近傍判定は必ずこのセンサーで行う。
private struct ReviewDiffVisibilitySensor: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReviewDiffVisibilitySensorView {
        ReviewDiffVisibilitySensorView()
    }

    func updateNSView(_ nsView: ReviewDiffVisibilitySensorView, context: Context) {
        nsView.onChange = onChange
    }
}

@MainActor
private final class ReviewDiffVisibilitySensorView: NSView {
    var onChange: ((Bool) -> Void)?
    private var lastIsNear: Bool?
    private weak var observedClipView: NSClipView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(geometryDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: self
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeEnclosingClipView()
        evaluate()
    }

    private func observeEnclosingClipView() {
        let clipView = enclosingScrollView?.contentView
        guard clipView !== observedClipView else { return }

        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView
            )
        }
        observedClipView = clipView
        if let clipView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(geometryDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
    }

    @objc private func geometryDidChange(_ notification: Notification) {
        evaluate()
    }

    private func evaluate() {
        guard window != nil else { return }

        let isNear: Bool
        if let clipView = enclosingScrollView?.contentView {
            isNear = ReviewDiffScrollLayout.isNearViewport(
                rowFrame: bounds,
                viewportBounds: convert(clipView.bounds, from: clipView)
            )
        } else {
            isNear = true
        }
        guard isNear != lastIsNear else { return }
        lastIsNear = isNear

        // 通知はレイアウトパス中にも届くため、SwiftUIのstate更新は次のランループへ。
        let onChange = onChange
        DispatchQueue.main.async {
            onChange?(isNear)
        }
    }
}

// MARK: - Horizontal Scroll Sync

/// 同一ファイル内のチャンク間で横スクロール位置を同期するグループ。
/// side-by-side では old/new の列ごとに独立したグループを持つ。
@MainActor
private final class ReviewDiffFileHorizontalSyncGroups {
    let unified = ReviewDiffPaneHorizontalSync()
    let old = ReviewDiffPaneHorizontalSync()
    let new = ReviewDiffPaneHorizontalSync()
}

@MainActor
private final class ReviewDiffPaneHorizontalSync {
    private let panes = NSHashTable<ReviewDiffTextPaneAppKitView>.weakObjects()
    private(set) var originX: CGFloat = 0

    func register(_ pane: ReviewDiffTextPaneAppKitView) {
        panes.add(pane)
    }

    func paneDidScroll(_ pane: ReviewDiffTextPaneAppKitView, toOriginX originX: CGFloat) {
        guard abs(originX - self.originX) > 0.5 else { return }
        self.originX = originX
        for member in panes.allObjects where member !== pane {
            member.applySyncedHorizontalOrigin(originX)
        }
    }

    func reset() {
        originX = 0
    }
}

// MARK: - Text Pane Representable

private struct ReviewDiffTextPane: NSViewRepresentable {
    let document: ReviewDiffRenderedDocument
    let minimumCodeWidth: CGFloat
    let syntaxHighlights: ReviewDiffSyntaxHighlights
    let wrapLines: Bool
    let horizontalSync: ReviewDiffPaneHorizontalSync?
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?

    func makeNSView(context: Context) -> ReviewDiffTextPaneAppKitView {
        ReviewDiffTextPaneAppKitView()
    }

    func updateNSView(_ nsView: ReviewDiffTextPaneAppKitView, context: Context) {
        nsView.update(
            document: document,
            minimumCodeWidth: minimumCodeWidth,
            syntaxHighlights: syntaxHighlights,
            wrapLines: wrapLines,
            horizontalSync: horizontalSync,
            requestCodeNavigation: requestCodeNavigation,
            codeNavigationHoverRange: codeNavigationHoverRange
        )
    }
}

// MARK: - Pane Scroll View

private final class ReviewDiffPaneClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        constrainedBounds.origin.y = 0
        return constrainedBounds
    }
}

private final class ReviewDiffPaneScrollView: NSScrollView {
    private var activeScrollWheelRoute: ReviewDiffScrollLayout.ScrollWheelRoute?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = ReviewDiffPaneClipView()
        verticalScrollElasticity = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func scrollWheel(with event: NSEvent) {
        let phase = Self.eventPhase(for: event)
        if phase == .gestureBegan {
            activeScrollWheelRoute = nil
        }

        let route = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: phase,
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            canScrollHorizontally: ReviewDiffScrollLayout.canScrollHorizontally(
                documentWidth: documentView?.frame.width ?? 0,
                viewportWidth: contentView.bounds.width
            ),
            activeRoute: activeScrollWheelRoute
        )
        if phase != .discrete {
            activeScrollWheelRoute = route
        }

        switch route {
        case .pane:
            super.scrollWheel(with: event)
        case .parent, nil:
            nextResponder?.scrollWheel(with: event)
        }
    }

    private static func eventPhase(for event: NSEvent) -> ReviewDiffScrollLayout.ScrollWheelEventPhase {
        if event.momentumPhase != [] {
            return .momentum
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            return .gestureBegan
        }
        if event.phase != [] {
            return .gestureActive
        }
        return .discrete
    }
}

// MARK: - Text Pane AppKit View

@MainActor
private final class ReviewDiffTextPaneAppKitView: NSView {
    private let scrollView = ReviewDiffPaneScrollView()
    private let textView = ReviewDiffTextView()
    private let gutterView: ReviewDiffTextGutterView
    private var gutterWidthConstraint: NSLayoutConstraint?
    private var document = ReviewDiffRenderedDocument.empty
    private var wrapLines = true
    private var minimumDocumentCodeWidth: CGFloat = 0
    private var horizontalSync: ReviewDiffPaneHorizontalSync?
    private var isApplyingSyncScroll = false
    private var hasReceivedDocument = false
    private var cachedIntrinsicHeight: CGFloat = ReviewDiffLayout.codeLineHeight
    private var lastMeasuredLayout: ReviewDiffScrollLayout.MeasurementSignature?

    override init(frame frameRect: NSRect) {
        gutterView = ReviewDiffTextGutterView(textView: textView)
        super.init(frame: frameRect)
        setup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: cachedIntrinsicHeight)
    }

    override func layout() {
        super.layout()
        updateTextLayout(resetHorizontalScroll: false)
    }

    func update(
        document: ReviewDiffRenderedDocument,
        minimumCodeWidth: CGFloat,
        syntaxHighlights: ReviewDiffSyntaxHighlights,
        wrapLines: Bool,
        horizontalSync: ReviewDiffPaneHorizontalSync?,
        requestCodeNavigation: @escaping (ReviewDiffCodeNavigationRequest) -> Void,
        codeNavigationHoverRange: @escaping (ReviewDiffCodeNavigationRequest) async -> NSRange?
    ) {
        // 初回update(近傍実体化直後)はコンテンツ変更ではないため、同期グループの
        // 現在の横スクロール位置を引き継ぐ(リセットすると兄弟チャンクとずれる)。
        let isInitialUpdate = !hasReceivedDocument
        hasReceivedDocument = true
        let didChangeDocument = self.document != document
        let didChangeWrap = self.wrapLines != wrapLines
        let didChangeMinimumWidth = self.minimumDocumentCodeWidth != minimumCodeWidth
        self.document = document
        self.wrapLines = wrapLines
        self.minimumDocumentCodeWidth = minimumCodeWidth
        self.horizontalSync = horizontalSync
        horizontalSync?.register(self)

        scrollView.hasHorizontalScroller = !wrapLines
        textView.update(
            document: document,
            attributedString: ReviewDiffAttributedStringBuilder.attributedString(
                for: document,
                syntaxHighlights: syntaxHighlights
            ),
            requestCodeNavigation: requestCodeNavigation,
            codeNavigationHoverRange: codeNavigationHoverRange
        )
        gutterView.document = document
        gutterView.needsDisplay = true

        let didChangeContent = (didChangeDocument && !isInitialUpdate) || didChangeWrap
        if didChangeDocument || didChangeWrap || didChangeMinimumWidth {
            textView.resetCodeNavigationHover()
            lastMeasuredLayout = nil
        }
        if didChangeDocument {
            updateCachedIntrinsicHeight(estimatedDocumentHeight())
        }
        if didChangeContent {
            horizontalSync?.reset()
        }
        updateTextLayout(resetHorizontalScroll: didChangeContent)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutterView)
        addSubview(scrollView)
        let gutterWidthConstraint = gutterView.widthAnchor.constraint(equalToConstant: gutterView.calculatedRuleThickness)
        self.gutterWidthConstraint = gutterWidthConstraint

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,

            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        textView.textContainerInset = ReviewDiffLayout.textContainerInset
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    private func updateTextLayout(resetHorizontalScroll: Bool) {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }

        let gutterWidth = updateGutterWidth()
        guard let viewportWidth = ReviewDiffScrollLayout.measurableViewportWidth(
            totalWidth: bounds.width,
            gutterWidth: gutterWidth
        ) else {
            return
        }
        let textWidth = ReviewDiffScrollLayout.textWidth(
            viewportWidth: viewportWidth,
            // 同一ファイルの全チャンクで横スクロール範囲を揃えるため、
            // ファイル全体の最大コード幅を下限として使う。
            documentCodeWidth: max(document.maximumCodeWidth, minimumDocumentCodeWidth),
            textInsetWidth: textView.textContainerInset.width,
            wrapLines: wrapLines
        )
        // layout() はAppKitのレイアウトパスごとに呼ばれる。行高固定のため計測結果は
        // (textWidth, wrapLines) にしか依存せず、署名一致なら ensureLayout・frame設定・
        // intrinsic更新をすべてスキップしてレイアウトの連鎖増幅を断つ。
        let signature = ReviewDiffScrollLayout.MeasurementSignature(
            textWidth: textWidth,
            wrapLines: wrapLines
        )
        guard ReviewDiffScrollLayout.needsRemeasure(
            previous: lastMeasuredLayout,
            candidate: signature,
            forced: resetHorizontalScroll
        ) else {
            return
        }
        if wrapLines {
            textView.isHorizontallyResizable = false
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(
                width: textWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.lineBreakMode = .byWordWrapping
        } else {
            textView.isHorizontallyResizable = true
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textContainer.lineBreakMode = .byClipping
        }

        textView.isVerticallyResizable = true
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let measuredHeight = max(
            ReviewDiffLayout.codeLineHeight,
            ceil(usedRect.height + textView.textContainerInset.height * 2)
        )
        // setFrame がジオメトリ変更通知(ウィンドウ全体のスクロールビュー追跡再登録)の
        // 発火源になるため、実際に変化があるときだけ書き込む。
        let newFrame = NSRect(x: 0, y: 0, width: textWidth, height: measuredHeight)
        if textView.frame != newFrame {
            textView.frame = newFrame
        }
        let horizontalOrigin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: horizontalSync?.originX ?? scrollView.contentView.bounds.minX,
            documentWidth: textWidth,
            viewportWidth: viewportWidth,
            reset: resetHorizontalScroll
        )
        isApplyingSyncScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: horizontalOrigin, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isApplyingSyncScroll = false
        gutterView.needsDisplay = true

        lastMeasuredLayout = signature
        updateCachedIntrinsicHeight(measuredHeight)
    }

    func applySyncedHorizontalOrigin(_ originX: CGFloat) {
        isApplyingSyncScroll = true
        defer { isApplyingSyncScroll = false }
        let clamped = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: originX,
            documentWidth: textView.frame.width,
            viewportWidth: scrollView.contentView.bounds.width,
            reset: false
        )
        scrollView.contentView.scroll(to: NSPoint(x: clamped, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func estimatedDocumentHeight() -> CGFloat {
        ReviewDiffScrollLayout.estimatedDocumentHeight(
            lineCount: document.lineCount,
            lineHeight: ReviewDiffLayout.codeLineHeight,
            textInsetHeight: ReviewDiffLayout.textContainerInset.height
        )
    }

    private func updateCachedIntrinsicHeight(_ height: CGFloat) {
        guard abs(cachedIntrinsicHeight - height) > 0.5 else { return }
        cachedIntrinsicHeight = height
        invalidateIntrinsicContentSize()
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        gutterView.needsDisplay = true
        if !isApplyingSyncScroll {
            horizontalSync?.paneDidScroll(self, toOriginX: scrollView.contentView.bounds.minX)
        }
    }

    @discardableResult
    private func updateGutterWidth() -> CGFloat {
        let gutterWidth = gutterView.calculatedRuleThickness
        if abs((gutterWidthConstraint?.constant ?? 0) - gutterWidth) > .ulpOfOne {
            gutterWidthConstraint?.constant = gutterWidth
        }
        return gutterWidth
    }

}

// MARK: - Attributed String Builder

enum ReviewDiffAttributedStringBuilder {
    static func attributedString(
        for document: ReviewDiffRenderedDocument,
        syntaxHighlights: ReviewDiffSyntaxHighlights
    ) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: ReviewDiffLayout.codeFontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = ReviewDiffLayout.codeLineHeight
        paragraphStyle.maximumLineHeight = ReviewDiffLayout.codeLineHeight
        paragraphStyle.defaultTabInterval = ReviewDiffLayout.tabWidth
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedString = NSMutableAttributedString(
            string: document.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        for line in document.lines {
            switch line.kind {
            case .hunkHeader:
                let range = line.contentRange.clamped(toUTF16Length: attributedString.length)
                guard range.length > 0 else { continue }
                attributedString.addAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFont.monospacedSystemFont(
                            ofSize: ReviewDiffLayout.codeFontSize,
                            weight: .medium
                        )
                    ],
                    range: range
                )

            case .placeholder:
                let range = line.contentRange.clamped(toUTF16Length: attributedString.length)
                guard range.length > 0 else { continue }
                attributedString.addAttribute(
                    .foregroundColor,
                    value: NSColor.clear,
                    range: range
                )

            case .context, .addition, .deletion:
                let lineRange = line.contentRange.clamped(toUTF16Length: attributedString.length)
                guard lineRange.length > 0,
                      let syntaxLine = line.syntaxLine(in: syntaxHighlights) else {
                    continue
                }
                var cursor = lineRange.location
                let lineEnd = NSMaxRange(lineRange)
                for segment in syntaxLine.segments {
                    guard cursor < lineEnd else { break }
                    let length = segment.text.utf16.count
                    guard length > 0 else { continue }
                    let segmentRange = NSRange(
                        location: cursor,
                        length: min(length, lineEnd - cursor)
                    ).clamped(toUTF16Length: attributedString.length)
                    if let role = segment.role {
                        guard segmentRange.length > 0 else { continue }
                        attributedString.addAttribute(
                            .foregroundColor,
                            value: SyntaxHighlightPalette.color(
                                for: role,
                                themeName: syntaxHighlights.themeName
                            ),
                            range: segmentRange
                        )
                    }
                    cursor = NSMaxRange(segmentRange)
                }
            }
        }

        return attributedString
    }
}

// MARK: - Gutter View

private final class ReviewDiffTextGutterView: NSView {
    var document = ReviewDiffRenderedDocument.empty {
        didSet {
            needsDisplay = true
        }
    }

    private weak var textView: ReviewDiffTextView?

    override var isFlipped: Bool {
        true
    }

    init(textView: ReviewDiffTextView) {
        self.textView = textView
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var calculatedRuleThickness: CGFloat {
        let columns = CGFloat(document.pane.gutterColumnCount)
        return columns * ReviewDiffLayout.lineNumberColumnWidth
            + ReviewDiffLayout.markerWidth
            + 8
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        for line in document.lines {
            drawBackground(
                for: line,
                dirtyRect: dirtyRect,
                in: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
            drawGutter(
                for: line,
                dirtyRect: dirtyRect,
                in: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }
    }

    private func drawBackground() {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        let separatorWidth = 1 / backingScaleFactor
        NSRect(
            x: bounds.maxX - separatorWidth,
            y: bounds.minY,
            width: separatorWidth,
            height: bounds.height
        ).fill()
    }

    private func drawBackground(
        for line: ReviewDiffRenderedLine,
        dirtyRect: NSRect,
        in textView: ReviewDiffTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        let color = line.backgroundColor(for: effectiveAppearance)
        guard color.alphaComponent > 0 else { return }

        color.setFill()
        for rect in visualRects(for: line, in: textView, layoutManager: layoutManager, textContainer: textContainer) {
            let backgroundRect = NSRect(x: bounds.minX, y: rect.minY, width: bounds.width, height: rect.height)
            if backgroundRect.intersects(dirtyRect) {
                backgroundRect.fill()
            }
        }
    }

    private func drawGutter(
        for line: ReviewDiffRenderedLine,
        dirtyRect: NSRect,
        in textView: ReviewDiffTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        guard let rect = visualRects(
            for: line,
            in: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        ).first else {
            return
        }
        guard rect.intersects(dirtyRect) else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: ReviewDiffLayout.codeFontSize,
                weight: .regular
            ),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        switch document.pane {
        case .unified:
            drawLineNumber(line.oldLineNumber, column: 0, y: rect.minY, height: rect.height, attributes: attributes)
            drawLineNumber(line.newLineNumber, column: 1, y: rect.minY, height: rect.height, attributes: attributes)
            drawMarker(line.marker, columnOffset: ReviewDiffLayout.lineNumberColumnWidth * 2, y: rect.minY, height: rect.height)

        case .old:
            drawLineNumber(line.oldLineNumber, column: 0, y: rect.minY, height: rect.height, attributes: attributes)
            drawMarker(line.marker, columnOffset: ReviewDiffLayout.lineNumberColumnWidth, y: rect.minY, height: rect.height)

        case .new:
            drawLineNumber(line.newLineNumber, column: 0, y: rect.minY, height: rect.height, attributes: attributes)
            drawMarker(line.marker, columnOffset: ReviewDiffLayout.lineNumberColumnWidth, y: rect.minY, height: rect.height)
        }
    }

    private func drawLineNumber(
        _ lineNumber: Int?,
        column: Int,
        y: CGFloat,
        height: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let lineNumber else { return }

        let string = "\(lineNumber)" as NSString
        let size = string.size(withAttributes: attributes)
        let columnOrigin = CGFloat(column) * ReviewDiffLayout.lineNumberColumnWidth
        let x = columnOrigin
            + ReviewDiffLayout.lineNumberWidth
            - size.width
        string.draw(
            at: NSPoint(
                x: x,
                y: y + max(0, (height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }

    private func drawMarker(
        _ marker: String,
        columnOffset: CGFloat,
        y: CGFloat,
        height: CGFloat
    ) {
        guard !marker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: ReviewDiffLayout.codeFontSize, weight: .regular),
            .foregroundColor: marker == "+" ? NSColor.systemGreen : NSColor.systemRed
        ]
        let string = marker as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(
            at: NSPoint(
                x: columnOffset + max(0, (ReviewDiffLayout.markerWidth - size.width) / 2),
                y: y + max(0, (height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }

    private func visualRects(
        for line: ReviewDiffRenderedLine,
        in textView: ReviewDiffTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [NSRect] {
        let relativePoint = convert(NSPoint.zero, from: textView)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: line.contentRange,
            actualCharacterRange: nil
        )
        var rects: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            rects.append(NSRect(
                x: self.bounds.minX,
                y: lineRect.minY + textView.textContainerOrigin.y + relativePoint.y,
                width: self.bounds.width,
                height: max(1, lineRect.height)
            ))
        }
        return rects
    }

    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }
}

// MARK: - Diff Text View

private final class ReviewDiffTextView: NSTextView {
    private var document = ReviewDiffRenderedDocument.empty
    private var codeNavigationHandler: ((ReviewDiffCodeNavigationRequest) -> Void)?
    private var codeNavigationHoverRangeProvider: ((ReviewDiffCodeNavigationRequest) async -> NSRange?)?
    private var codeNavigationTrackingArea: NSTrackingArea?
    private var codeNavigationHoverTask: Task<Void, Never>?
    private var codeNavigationHoverRequestID: UUID?
    private var codeNavigationHoverQueryRange: TextRange?
    private var activeCodeNavigationHoverRange: NSRange?
    private var codeNavigationHoverHitCache: [TextRange: TextRange] = [:]
    private var codeNavigationHoverMissCache = Set<TextRange>()

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        super.init(frame: .zero, textContainer: textContainer)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        codeNavigationHoverTask?.cancel()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawLineBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let codeNavigationTrackingArea {
            removeTrackingArea(codeNavigationTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        codeNavigationTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: activeCodeNavigationHoverRange == nil ? .iBeam : .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let request = navigationRequest(at: event) {
            codeNavigationHandler?(request)
            return
        }

        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCodeNavigationHover(windowPoint: event.locationInWindow, modifierFlags: event.modifierFlags)
    }

    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    ) -> NSRange {
        let fallback = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        guard granularity == .selectByWord else { return fallback }

        return EditorWordSelection.wordSelectionRange(
            in: string as NSString,
            proposedRange: proposedCharRange,
            fallback: fallback
        )
    }

    override func mouseExited(with event: NSEvent) {
        clearCodeNavigationHover()
        super.mouseExited(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else {
            clearCodeNavigationHover()
            return
        }
        updateCodeNavigationHover(
            windowPoint: window.mouseLocationOutsideOfEventStream,
            modifierFlags: event.modifierFlags
        )
    }

    func update(
        document: ReviewDiffRenderedDocument,
        attributedString: NSAttributedString,
        requestCodeNavigation: @escaping (ReviewDiffCodeNavigationRequest) -> Void,
        codeNavigationHoverRange: @escaping (ReviewDiffCodeNavigationRequest) async -> NSRange?
    ) {
        let didChangeDocument = self.document != document
        self.document = document
        codeNavigationHandler = requestCodeNavigation
        codeNavigationHoverRangeProvider = codeNavigationHoverRange

        if textStorage?.isEqual(to: attributedString) != true {
            textStorage?.setAttributedString(attributedString)
        }

        if didChangeDocument {
            resetCodeNavigationHover()
        }
        needsDisplay = true
    }

    func resetCodeNavigationHover() {
        codeNavigationHoverHitCache.removeAll()
        codeNavigationHoverMissCache.removeAll()
        clearCodeNavigationHover()
    }

    // MARK: - Text View Setup & Drawing

    private func configure() {
        drawsBackground = false
        isEditable = false
        isSelectable = true
        isRichText = true
        importsGraphics = false
        allowsUndo = false
        usesFontPanel = false
        usesFindBar = false
        textContainerInset = NSSize(width: 8, height: 6)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func drawLineBackgrounds(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        for line in document.lines {
            let color = line.backgroundColor(for: effectiveAppearance)
            guard color.alphaComponent > 0 else { continue }

            color.setFill()
            for rect in visualRects(for: line, layoutManager: layoutManager, textContainer: textContainer) {
                let backgroundRect = NSRect(
                    x: bounds.minX,
                    y: rect.minY,
                    width: bounds.width,
                    height: rect.height
                )
                if backgroundRect.intersects(dirtyRect) {
                    backgroundRect.fill()
                }
            }
        }
    }

    // MARK: - Code Navigation Hover

    private func navigationRequest(at event: NSEvent) -> ReviewDiffCodeNavigationRequest? {
        guard let location = utf16Location(atWindowPoint: event.locationInWindow),
              let line = document.line(containingUTF16Location: location) else {
            return nil
        }

        return line.navigationRequest(atUTF16Location: location)
    }

    private func updateCodeNavigationHover(
        windowPoint: NSPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard modifierFlags.contains(.command),
              let codeNavigationHoverRangeProvider,
              let location = utf16Location(atWindowPoint: windowPoint),
              let line = document.line(containingUTF16Location: location),
              let request = line.navigationRequest(atUTF16Location: location),
              let identifierRange = identifierRange(at: location, within: line.contentRange) else {
            clearCodeNavigationHover()
            return
        }

        NSCursor.pointingHand.set()
        let queryRange = TextRange(location: identifierRange.location, length: identifierRange.length)
        guard codeNavigationHoverQueryRange != queryRange else {
            return
        }

        codeNavigationHoverTask?.cancel()
        codeNavigationHoverTask = nil
        codeNavigationHoverRequestID = UUID()
        codeNavigationHoverQueryRange = queryRange
        setCodeNavigationHoverRange(nil)

        if let cachedRange = codeNavigationHoverHitCache[queryRange] {
            setCodeNavigationHoverRange(cachedRange.nsRange)
            return
        }

        guard !codeNavigationHoverMissCache.contains(queryRange),
              let requestID = codeNavigationHoverRequestID else {
            NSCursor.pointingHand.set()
            return
        }

        codeNavigationHoverTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 70_000_000)
            } catch {
                return
            }

            guard let self,
                  self.codeNavigationHoverRequestID == requestID,
                  self.codeNavigationHoverQueryRange == queryRange else {
                return
            }

            let resolvedLineRange = await codeNavigationHoverRangeProvider(request)
            guard self.codeNavigationHoverRequestID == requestID,
                  self.codeNavigationHoverQueryRange == queryRange else {
                return
            }

            if let resolvedLineRange,
               resolvedLineRange.length > 0 {
                let documentRange = NSRange(
                    location: line.contentRange.location + resolvedLineRange.location,
                    length: min(
                        resolvedLineRange.length,
                        max(0, NSMaxRange(line.contentRange) - line.contentRange.location - resolvedLineRange.location)
                    )
                ).clamped(toUTF16Length: self.string.utf16.count)
                let hoverRange = TextRange(location: documentRange.location, length: documentRange.length)
                self.codeNavigationHoverHitCache[queryRange] = hoverRange
                self.setCodeNavigationHoverRange(documentRange)
            } else {
                self.codeNavigationHoverMissCache.insert(queryRange)
                self.setCodeNavigationHoverRange(nil)
                NSCursor.pointingHand.set()
            }

            self.codeNavigationHoverTask = nil
        }
    }

    private func clearCodeNavigationHover() {
        codeNavigationHoverTask?.cancel()
        codeNavigationHoverTask = nil
        codeNavigationHoverRequestID = nil
        codeNavigationHoverQueryRange = nil
        setCodeNavigationHoverRange(nil)
    }

    private func setCodeNavigationHoverRange(_ range: NSRange?) {
        let textLength = string.utf16.count
        let validRange = range?
            .clamped(toUTF16Length: textLength)
            .nonEmpty

        if let activeCodeNavigationHoverRange,
           let validRange,
           NSEqualRanges(activeCodeNavigationHoverRange, validRange) {
            NSCursor.pointingHand.set()
            return
        }

        if let oldRange = activeCodeNavigationHoverRange?.clamped(toUTF16Length: textLength).nonEmpty {
            layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: oldRange)
            layoutManager?.removeTemporaryAttribute(.underlineColor, forCharacterRange: oldRange)
        }

        let hadActiveRange = activeCodeNavigationHoverRange != nil
        activeCodeNavigationHoverRange = validRange

        if let validRange {
            layoutManager?.addTemporaryAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.controlAccentColor
                ],
                forCharacterRange: validRange
            )
            NSCursor.pointingHand.set()
        }

        if hadActiveRange != (activeCodeNavigationHoverRange != nil) {
            window?.invalidateCursorRects(for: self)
        }
        needsDisplay = true
    }

    // MARK: - Hit Testing Helpers

    private func utf16Location(atWindowPoint windowPoint: NSPoint) -> Int? {
        guard let layoutManager,
              let textContainer,
              layoutManager.numberOfGlyphs > 0 else {
            return nil
        }

        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point) else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer).insetBy(dx: -2, dy: -2)
        guard usedRect.contains(containerPoint) else { return nil }

        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        return min(max(0, layoutManager.characterIndexForGlyph(at: glyphIndex)), string.utf16.count)
    }

    private func identifierRange(at location: Int, within contentRange: NSRange) -> NSRange? {
        let string = self.string as NSString
        let contentRange = contentRange.clamped(toUTF16Length: string.length)
        guard contentRange.length > 0 else { return nil }

        var offset = min(max(contentRange.location, location), NSMaxRange(contentRange) - 1)
        if !isIdentifierCharacter(string.character(at: offset)),
           offset > contentRange.location,
           isIdentifierCharacter(string.character(at: offset - 1)) {
            offset -= 1
        }

        guard isIdentifierCharacter(string.character(at: offset)) else { return nil }

        var start = offset
        while start > contentRange.location && isIdentifierCharacter(string.character(at: start - 1)) {
            start -= 1
        }

        var end = offset + 1
        while end < NSMaxRange(contentRange) && isIdentifierCharacter(string.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    private func visualRects(
        for line: ReviewDiffRenderedLine,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [NSRect] {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: line.contentRange,
            actualCharacterRange: nil
        )
        var rects: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            rects.append(NSRect(
                x: self.bounds.minX,
                y: lineRect.minY + self.textContainerOrigin.y,
                width: self.bounds.width,
                height: max(1, lineRect.height)
            ))
        }
        return rects
    }

    private func isIdentifierCharacter(_ character: unichar) -> Bool {
        EditorOccurrenceHighlighter.isIdentifierCharacter(character)
    }
}

// MARK: - Private Extensions

private extension ReviewDiffRenderedLine {
    func syntaxLine(in highlights: ReviewDiffSyntaxHighlights) -> ReviewDiffSyntaxLine? {
        syntaxKey.flatMap { highlights.line(for: $0) }
            ?? fallbackSyntaxKey.flatMap { highlights.line(for: $0) }
    }

    func backgroundColor(for appearance: NSAppearance) -> NSColor {
        switch kind {
        case .hunkHeader:
            NSColor.controlAccentColor.withAlphaComponent(0.08)
        case .addition:
            NSColor.systemGreen.withAlphaComponent(0.12)
        case .deletion:
            NSColor.systemRed.withAlphaComponent(0.12)
        case .context, .placeholder:
            NSColor.clear
        }
    }
}

private extension ReviewDiffLayout {
    static var tabWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        return ("    " as NSString).size(withAttributes: [.font: font]).width
    }
}

#Preview {
    ReviewDiffView(
        showsFocusLine: false,
        state: .loaded(GitReviewDiffSnapshot(
            baseBranch: "main",
            targetBranch: .branch("feature/review"),
            targetWorktreeRootURL: URL(filePath: "/tmp/repo"),
            mergeBaseRevision: "abc123",
            files: [
                GitReviewFileDiff(diff: SourceFileDiff(
                    oldRelativePath: "Sources/App.swift",
                    newRelativePath: "Sources/App.swift",
                    hunks: [
                        SourceDiffHunk(
                            oldStart: 1,
                            oldLineCount: 2,
                            newStart: 1,
                            newLineCount: 3,
                            lines: [
                                SourceDiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "import SwiftUI"),
                                SourceDiffLine(kind: .deletion, oldLineNumber: 2, newLineNumber: nil, content: "Text(\"Old\")"),
                                SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, content: "Text(\"New\")"),
                                SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 3, content: "Text(\"Review\")")
                            ]
                        )
                    ]
                ))
            ]
        )),
        selectedBase: .branch("main"),
        localBranches: [GitLocalBranchInfo(name: "main", checkedOutWorktreeURL: nil)],
        remoteBranches: [],
        isLoadingRemoteBranches: false,
        remoteBranchErrorMessage: nil,
        hideWhitespace: false,
        viewedFilePaths: [],
        viewedStateSyncsToPullRequest: false,
        displayMode: .constant(.unified),
        wrapLines: .constant(true),
        selectBase: { _ in },
        loadRemoteBranches: { _ in },
        refresh: {},
        setHideWhitespace: { _ in },
        setFileViewed: { _, _ in },
        openFile: { _ in },
        requestCodeNavigation: { _ in },
        codeNavigationHoverRange: { _ in nil }
    )
}

private extension NSRange {
    var nonEmpty: NSRange? {
        length > 0 ? self : nil
    }
}
