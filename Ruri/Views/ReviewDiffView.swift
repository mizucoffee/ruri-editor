//
//  ReviewDiffView.swift
//  ruri
//

import AppKit
import SwiftUI

struct ReviewDiffView: View {
    let state: ReviewDiffState
    let selectedBase: GitReviewDiffBase?
    let localBranches: [GitLocalBranchInfo]
    let remoteBranches: [GitRemoteBranchInfo]
    let isLoadingRemoteBranches: Bool
    let remoteBranchErrorMessage: String?
    let hideWhitespace: Bool
    @Binding var displayMode: ReviewDiffDisplayMode
    @Binding var wrapLines: Bool
    let selectBase: (GitReviewDiffBase) -> Void
    let loadRemoteBranches: (Bool) -> Void
    let refresh: () -> Void
    let setHideWhitespace: (Bool) -> Void
    let openFile: (URL) -> Void
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
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
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(snapshot.files) { file in
                            ReviewDiffFileView(
                                file: file,
                                targetWorktreeRootURL: snapshot.targetWorktreeRootURL,
                                displayMode: displayMode,
                                wrapLines: wrapLines,
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
}

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

private struct ReviewDiffFileView: View {
    let file: GitReviewFileDiff
    let targetWorktreeRootURL: URL
    let displayMode: ReviewDiffDisplayMode
    let wrapLines: Bool
    let openFile: (URL) -> Void
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true
    @State private var syntaxHighlights = ReviewDiffSyntaxHighlights.empty

    var body: some View {
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
                        syntaxHighlights: syntaxHighlights,
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
        .task(id: syntaxHighlightRequestID) {
            guard isExpanded else {
                syntaxHighlights = .empty
                return
            }

            syntaxHighlights = await ReviewDiffSyntaxHighlighter.highlights(
                for: file,
                colorScheme: colorScheme
            )
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
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

enum ReviewDiffSyntaxSide: Hashable, Sendable {
    case old
    case new
}

struct ReviewDiffLineKey: Hashable, Sendable {
    let hunkIndex: Int
    let lineIndex: Int
    let side: ReviewDiffSyntaxSide
}

private struct ReviewDiffSyntaxSegment: Equatable, Sendable {
    let text: String
    let role: SyntaxHighlightRole?
}

private struct ReviewDiffSyntaxLine: Equatable, Sendable {
    let segments: [ReviewDiffSyntaxSegment]
}

private struct ReviewDiffSyntaxHighlights: Sendable {
    static let empty = ReviewDiffSyntaxHighlights(linesByKey: [:], themeName: "tree-sitter-light")

    let linesByKey: [ReviewDiffLineKey: ReviewDiffSyntaxLine]
    let themeName: String

    func line(for key: ReviewDiffLineKey) -> ReviewDiffSyntaxLine? {
        linesByKey[key]
    }

    func line(
        hunkIndex: Int,
        lineIndex: Int,
        side: ReviewDiffSyntaxSide,
        fallbackSide: ReviewDiffSyntaxSide? = nil
    ) -> ReviewDiffSyntaxLine? {
        line(for: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: side))
            ?? fallbackSide.flatMap {
                line(for: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: $0))
            }
    }
}

private enum ReviewDiffSyntaxHighlighter {
    static func highlights(
        for file: GitReviewFileDiff,
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

        return ReviewDiffSyntaxHighlights(linesByKey: linesByKey, themeName: themeName)
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

private extension SourceDiffLine {
    var unifiedSyntaxSide: ReviewDiffSyntaxSide {
        kind == .deletion ? .old : .new
    }
}

private enum ReviewDiffLayout {
    static let minimumContentWidth: CGFloat = 760
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

struct ReviewDiffRenderedDocument: Equatable {
    enum Pane: Equatable {
        case unified
        case old
        case new

        var gutterColumnCount: Int {
            switch self {
            case .unified:
                2
            case .old, .new:
                1
            }
        }
    }

    static let empty = ReviewDiffRenderedDocument(
        pane: .unified,
        text: " ",
        lines: [
            ReviewDiffRenderedLine(
                kind: .placeholder,
                oldLineNumber: nil,
                newLineNumber: nil,
                marker: " ",
                contentRange: NSRange(location: 0, length: 1),
                sourceContentUTF16Length: 0,
                sourceFileURL: nil,
                navigationSide: nil,
                sourceLineNumber: nil,
                syntaxKey: nil,
                fallbackSyntaxKey: nil
            )
        ],
        maximumCodeWidth: ReviewDiffLayout.codeWidth(for: " ")
    )

    let pane: Pane
    let text: String
    let lines: [ReviewDiffRenderedLine]
    let maximumCodeWidth: CGFloat

    var lineCount: Int {
        lines.count
    }

    static func unified(
        file: GitReviewFileDiff,
        oldFileURL: URL?,
        newFileURL: URL?
    ) -> ReviewDiffRenderedDocument {
        var builder = ReviewDiffRenderedDocumentBuilder(pane: .unified)

        for (hunkIndex, hunk) in file.diff.hunks.enumerated() {
            builder.appendHunkHeader(hunk)

            for (lineIndex, line) in hunk.lines.enumerated() {
                let syntaxSide = line.unifiedSyntaxSide
                let fallbackSyntaxSide: ReviewDiffSyntaxSide? = syntaxSide == .new ? .old : .new
                let fileURL = line.kind == .deletion ? oldFileURL : newFileURL
                let lineNumber = line.kind == .deletion ? line.oldLineNumber : line.newLineNumber
                builder.appendCodeLine(
                    content: line.content,
                    kind: ReviewDiffRenderedLine.Kind(line.kind),
                    oldLineNumber: line.oldLineNumber,
                    newLineNumber: line.newLineNumber,
                    marker: line.unifiedMarker,
                    sourceFileURL: fileURL,
                    navigationSide: line.kind == .deletion ? .old : .new,
                    sourceLineNumber: lineNumber,
                    syntaxKey: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: syntaxSide),
                    fallbackSyntaxKey: fallbackSyntaxSide.map {
                        ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: $0)
                    }
                )
            }
        }

        return builder.build()
    }

    static func sideBySide(
        file: GitReviewFileDiff,
        side: ReviewDiffSyntaxSide,
        fileURL: URL?
    ) -> ReviewDiffRenderedDocument {
        var builder = ReviewDiffRenderedDocumentBuilder(pane: side == .old ? .old : .new)

        for (hunkIndex, hunk) in file.diff.hunks.enumerated() {
            builder.appendHunkHeader(hunk)

            for row in ReviewDiffSideBySideRenderedRow.rows(hunkIndex: hunkIndex, lines: hunk.lines) {
                let indexedLine = side == .old ? row.oldLine : row.newLine
                guard let indexedLine else {
                    builder.appendPlaceholder()
                    continue
                }

                let line = indexedLine.line
                let lineNumber = side == .old ? line.oldLineNumber : line.newLineNumber
                builder.appendCodeLine(
                    content: line.content,
                    kind: ReviewDiffRenderedLine.Kind(line.kind),
                    oldLineNumber: side == .old ? line.oldLineNumber : nil,
                    newLineNumber: side == .new ? line.newLineNumber : nil,
                    marker: line.marker(for: side),
                    sourceFileURL: fileURL,
                    navigationSide: side == .old ? .old : .new,
                    sourceLineNumber: lineNumber,
                    syntaxKey: ReviewDiffLineKey(
                        hunkIndex: indexedLine.hunkIndex,
                        lineIndex: indexedLine.lineIndex,
                        side: side
                    ),
                    fallbackSyntaxKey: nil
                )
            }
        }

        return builder.build()
    }

    func line(containingUTF16Location location: Int) -> ReviewDiffRenderedLine? {
        guard !lines.isEmpty else { return nil }

        let clampedLocation = min(max(0, location), text.utf16.count)
        var lowerBound = 0
        var upperBound = lines.count - 1

        while lowerBound <= upperBound {
            let middle = (lowerBound + upperBound) / 2
            let line = lines[middle]
            let lineStart = line.contentRange.location
            let lineEnd = NSMaxRange(line.contentRange)

            if clampedLocation < lineStart {
                upperBound = middle - 1
            } else if clampedLocation > lineEnd {
                lowerBound = middle + 1
            } else {
                return line
            }
        }

        return lines.last { $0.contentRange.location <= clampedLocation }
    }
}

struct ReviewDiffRenderedLine: Equatable {
    enum Kind: Equatable {
        case hunkHeader
        case context
        case addition
        case deletion
        case placeholder
    }

    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let marker: String
    let contentRange: NSRange
    let sourceContentUTF16Length: Int
    let sourceFileURL: URL?
    let navigationSide: ReviewDiffCodeNavigationSide?
    let sourceLineNumber: Int?
    let syntaxKey: ReviewDiffLineKey?
    let fallbackSyntaxKey: ReviewDiffLineKey?

    var canNavigate: Bool {
        sourceFileURL != nil && navigationSide != nil && sourceLineNumber != nil
    }

    func navigationRequest(atUTF16Location location: Int) -> ReviewDiffCodeNavigationRequest? {
        guard let sourceFileURL,
              let navigationSide,
              let sourceLineNumber else {
            return nil
        }

        let column = min(
            max(0, location - contentRange.location),
            sourceContentUTF16Length
        )
        return ReviewDiffCodeNavigationRequest(
            fileURL: sourceFileURL,
            side: navigationSide,
            lineNumber: sourceLineNumber,
            utf16Column: column
        )
    }
}

private struct ReviewDiffRenderedDocumentBuilder {
    private(set) var text = ""
    private(set) var lines: [ReviewDiffRenderedLine] = []
    private var maximumCodeWidth = ReviewDiffLayout.codeWidth(for: " ")
    private let pane: ReviewDiffRenderedDocument.Pane

    init(pane: ReviewDiffRenderedDocument.Pane) {
        self.pane = pane
    }

    mutating func appendHunkHeader(_ hunk: SourceDiffHunk) {
        appendLine(
            content: "@@ -\(hunk.oldStart),\(hunk.oldLineCount) +\(hunk.newStart),\(hunk.newLineCount) @@",
            kind: .hunkHeader,
            oldLineNumber: nil,
            newLineNumber: nil,
            marker: " ",
            sourceContentUTF16Length: 0,
            sourceFileURL: nil,
            navigationSide: nil,
            sourceLineNumber: nil,
            syntaxKey: nil,
            fallbackSyntaxKey: nil
        )
    }

    mutating func appendPlaceholder() {
        appendLine(
            content: "",
            kind: .placeholder,
            oldLineNumber: nil,
            newLineNumber: nil,
            marker: " ",
            sourceContentUTF16Length: 0,
            sourceFileURL: nil,
            navigationSide: nil,
            sourceLineNumber: nil,
            syntaxKey: nil,
            fallbackSyntaxKey: nil
        )
    }

    mutating func appendCodeLine(
        content: String,
        kind: ReviewDiffRenderedLine.Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        marker: String,
        sourceFileURL: URL?,
        navigationSide: ReviewDiffCodeNavigationSide?,
        sourceLineNumber: Int?,
        syntaxKey: ReviewDiffLineKey?,
        fallbackSyntaxKey: ReviewDiffLineKey?
    ) {
        appendLine(
            content: content,
            kind: kind,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            marker: marker,
            sourceContentUTF16Length: content.utf16.count,
            sourceFileURL: sourceFileURL,
            navigationSide: navigationSide,
            sourceLineNumber: sourceLineNumber,
            syntaxKey: syntaxKey,
            fallbackSyntaxKey: fallbackSyntaxKey
        )
    }

    mutating func build() -> ReviewDiffRenderedDocument {
        if lines.isEmpty {
            appendPlaceholder()
        }

        return ReviewDiffRenderedDocument(
            pane: pane,
            text: text,
            lines: lines,
            maximumCodeWidth: maximumCodeWidth
        )
    }

    private mutating func appendLine(
        content: String,
        kind: ReviewDiffRenderedLine.Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        marker: String,
        sourceContentUTF16Length: Int,
        sourceFileURL: URL?,
        navigationSide: ReviewDiffCodeNavigationSide?,
        sourceLineNumber: Int?,
        syntaxKey: ReviewDiffLineKey?,
        fallbackSyntaxKey: ReviewDiffLineKey?
    ) {
        if !text.isEmpty {
            text += "\n"
        }

        let displayContent = content.isEmpty ? " " : content
        let start = text.utf16.count
        text += displayContent
        let contentRange = NSRange(location: start, length: displayContent.utf16.count)
        maximumCodeWidth = max(maximumCodeWidth, ReviewDiffLayout.codeWidth(for: displayContent))
        lines.append(ReviewDiffRenderedLine(
            kind: kind,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            marker: marker,
            contentRange: contentRange,
            sourceContentUTF16Length: sourceContentUTF16Length,
            sourceFileURL: sourceFileURL,
            navigationSide: navigationSide,
            sourceLineNumber: sourceLineNumber,
            syntaxKey: syntaxKey,
            fallbackSyntaxKey: fallbackSyntaxKey
        ))
    }
}

private struct ReviewIndexedDiffLine: Equatable {
    let hunkIndex: Int
    let lineIndex: Int
    let line: SourceDiffLine
}

private struct ReviewDiffSideBySideRenderedRow: Equatable {
    let oldLine: ReviewIndexedDiffLine?
    let newLine: ReviewIndexedDiffLine?

    static func rows(hunkIndex: Int, lines: [SourceDiffLine]) -> [ReviewDiffSideBySideRenderedRow] {
        let indexedLines = lines.enumerated().map { lineIndex, line in
            ReviewIndexedDiffLine(hunkIndex: hunkIndex, lineIndex: lineIndex, line: line)
        }
        var rows: [ReviewDiffSideBySideRenderedRow] = []
        var index = 0

        while index < indexedLines.count {
            let indexedLine = indexedLines[index]
            let line = indexedLine.line

            if line.kind == .context {
                rows.append(ReviewDiffSideBySideRenderedRow(oldLine: indexedLine, newLine: indexedLine))
                index += 1
                continue
            }

            if line.kind == .deletion {
                var deletions: [ReviewIndexedDiffLine] = []
                while index < indexedLines.count, indexedLines[index].line.kind == .deletion {
                    deletions.append(indexedLines[index])
                    index += 1
                }

                var additions: [ReviewIndexedDiffLine] = []
                while index < indexedLines.count, indexedLines[index].line.kind == .addition {
                    additions.append(indexedLines[index])
                    index += 1
                }

                appendPairedRows(oldLines: deletions, newLines: additions, to: &rows)
                continue
            }

            var additions: [ReviewIndexedDiffLine] = []
            while index < indexedLines.count, indexedLines[index].line.kind == .addition {
                additions.append(indexedLines[index])
                index += 1
            }
            appendPairedRows(oldLines: [], newLines: additions, to: &rows)
        }

        return rows
    }

    private static func appendPairedRows(
        oldLines: [ReviewIndexedDiffLine],
        newLines: [ReviewIndexedDiffLine],
        to rows: inout [ReviewDiffSideBySideRenderedRow]
    ) {
        let rowCount = max(oldLines.count, newLines.count)
        for offset in 0..<rowCount {
            rows.append(ReviewDiffSideBySideRenderedRow(
                oldLine: line(at: offset, in: oldLines),
                newLine: line(at: offset, in: newLines)
            ))
        }
    }

    private static func line(at index: Int, in lines: [ReviewIndexedDiffLine]) -> ReviewIndexedDiffLine? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index]
    }
}

private struct ReviewDiffFileContentView: View {
    let file: GitReviewFileDiff
    let oldFileURL: URL?
    let newFileURL: URL?
    let displayMode: ReviewDiffDisplayMode
    let wrapLines: Bool
    let syntaxHighlights: ReviewDiffSyntaxHighlights
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?

    var body: some View {
        switch displayMode {
        case .unified:
            let document = ReviewDiffRenderedDocument.unified(
                file: file,
                oldFileURL: oldFileURL,
                newFileURL: newFileURL
            )
            ReviewDiffTextPane(
                document: document,
                syntaxHighlights: syntaxHighlights,
                wrapLines: wrapLines,
                requestCodeNavigation: requestCodeNavigation,
                codeNavigationHoverRange: codeNavigationHoverRange
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: estimatedPaneHeight(for: document))
            .fixedSize(horizontal: false, vertical: true)

        case .sideBySide:
            let oldDocument = ReviewDiffRenderedDocument.sideBySide(
                file: file,
                side: .old,
                fileURL: oldFileURL
            )
            let newDocument = ReviewDiffRenderedDocument.sideBySide(
                file: file,
                side: .new,
                fileURL: newFileURL
            )
            HStack(alignment: .top, spacing: 0) {
                ReviewDiffTextPane(
                    document: oldDocument,
                    syntaxHighlights: syntaxHighlights,
                    wrapLines: false,
                    requestCodeNavigation: requestCodeNavigation,
                    codeNavigationHoverRange: codeNavigationHoverRange
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ReviewDiffTextPane(
                    document: newDocument,
                    syntaxHighlights: syntaxHighlights,
                    wrapLines: false,
                    requestCodeNavigation: requestCodeNavigation,
                    codeNavigationHoverRange: codeNavigationHoverRange
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: max(estimatedPaneHeight(for: oldDocument), estimatedPaneHeight(for: newDocument)))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func estimatedPaneHeight(for document: ReviewDiffRenderedDocument) -> CGFloat {
        ReviewDiffScrollLayout.estimatedDocumentHeight(
            lineCount: document.lineCount,
            lineHeight: ReviewDiffLayout.codeLineHeight,
            textInsetHeight: ReviewDiffLayout.textContainerInset.height
        )
    }
}

private struct ReviewDiffTextPane: NSViewRepresentable {
    let document: ReviewDiffRenderedDocument
    let syntaxHighlights: ReviewDiffSyntaxHighlights
    let wrapLines: Bool
    let requestCodeNavigation: (ReviewDiffCodeNavigationRequest) -> Void
    let codeNavigationHoverRange: (ReviewDiffCodeNavigationRequest) async -> NSRange?

    func makeNSView(context: Context) -> ReviewDiffTextPaneAppKitView {
        ReviewDiffTextPaneAppKitView()
    }

    func updateNSView(_ nsView: ReviewDiffTextPaneAppKitView, context: Context) {
        nsView.update(
            document: document,
            syntaxHighlights: syntaxHighlights,
            wrapLines: wrapLines,
            requestCodeNavigation: requestCodeNavigation,
            codeNavigationHoverRange: codeNavigationHoverRange
        )
    }
}

@MainActor
private final class ReviewDiffTextPaneAppKitView: NSView {
    private let scrollView = NSScrollView()
    private let textView = ReviewDiffTextView()
    private let gutterView: ReviewDiffTextGutterView
    private var gutterWidthConstraint: NSLayoutConstraint?
    private var document = ReviewDiffRenderedDocument.empty
    private var wrapLines = true
    private var cachedIntrinsicHeight: CGFloat = ReviewDiffLayout.codeLineHeight

    override init(frame frameRect: NSRect) {
        gutterView = ReviewDiffTextGutterView(textView: textView)
        super.init(frame: frameRect)
        setup()
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
        syntaxHighlights: ReviewDiffSyntaxHighlights,
        wrapLines: Bool,
        requestCodeNavigation: @escaping (ReviewDiffCodeNavigationRequest) -> Void,
        codeNavigationHoverRange: @escaping (ReviewDiffCodeNavigationRequest) async -> NSRange?
    ) {
        let didChangeDocument = self.document != document
        let didChangeWrap = self.wrapLines != wrapLines
        self.document = document
        self.wrapLines = wrapLines

        scrollView.hasHorizontalScroller = !wrapLines
        textView.update(
            document: document,
            attributedString: Self.attributedString(
                for: document,
                syntaxHighlights: syntaxHighlights
            ),
            requestCodeNavigation: requestCodeNavigation,
            codeNavigationHoverRange: codeNavigationHoverRange
        )
        gutterView.document = document
        gutterView.needsDisplay = true

        if didChangeDocument || didChangeWrap {
            textView.resetCodeNavigationHover()
        }
        if didChangeDocument {
            updateCachedIntrinsicHeight(estimatedDocumentHeight())
        }
        updateTextLayout(resetHorizontalScroll: didChangeDocument || didChangeWrap)
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
            documentCodeWidth: document.maximumCodeWidth,
            textInsetWidth: textView.textContainerInset.width,
            wrapLines: wrapLines
        )
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
        textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: measuredHeight)
        let horizontalOrigin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: scrollView.contentView.bounds.minX,
            documentWidth: textWidth,
            viewportWidth: viewportWidth,
            reset: resetHorizontalScroll
        )
        scrollView.contentView.scroll(to: NSPoint(x: horizontalOrigin, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        gutterView.needsDisplay = true

        updateCachedIntrinsicHeight(measuredHeight)
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

    @discardableResult
    private func updateGutterWidth() -> CGFloat {
        let gutterWidth = gutterView.calculatedRuleThickness
        if abs((gutterWidthConstraint?.constant ?? 0) - gutterWidth) > .ulpOfOne {
            gutterWidthConstraint?.constant = gutterWidth
        }
        return gutterWidth
    }

    private static func attributedString(
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
                attributedString.addAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFont.monospacedSystemFont(
                            ofSize: ReviewDiffLayout.codeFontSize,
                            weight: .medium
                        )
                    ],
                    range: line.contentRange
                )

            case .placeholder:
                attributedString.addAttribute(
                    .foregroundColor,
                    value: NSColor.clear,
                    range: line.contentRange
                )

            case .context, .addition, .deletion:
                guard let syntaxLine = line.syntaxLine(in: syntaxHighlights) else {
                    continue
                }
                var cursor = line.contentRange.location
                for segment in syntaxLine.segments {
                    let length = segment.text.utf16.count
                    guard length > 0 else { continue }
                    if let role = segment.role {
                        attributedString.addAttribute(
                            .foregroundColor,
                            value: SyntaxHighlightPalette.color(
                                for: role,
                                themeName: syntaxHighlights.themeName
                            ),
                            range: NSRange(location: cursor, length: length)
                        )
                    }
                    cursor += length
                }
            }
        }

        return attributedString
    }
}

enum ReviewDiffScrollLayout {
    static let minimumMeasurableViewportWidth: CGFloat = 80

    static func measurableViewportWidth(
        totalWidth: CGFloat,
        gutterWidth: CGFloat
    ) -> CGFloat? {
        let viewportWidth = totalWidth - gutterWidth
        guard viewportWidth >= minimumMeasurableViewportWidth else {
            return nil
        }
        return viewportWidth
    }

    static func textWidth(
        viewportWidth: CGFloat,
        documentCodeWidth: CGFloat,
        textInsetWidth: CGFloat,
        wrapLines: Bool
    ) -> CGFloat {
        guard !wrapLines else {
            return viewportWidth
        }

        return max(viewportWidth, documentCodeWidth + textInsetWidth * 2)
    }

    static func estimatedDocumentHeight(
        lineCount: Int,
        lineHeight: CGFloat,
        textInsetHeight: CGFloat
    ) -> CGFloat {
        max(lineHeight, CGFloat(max(1, lineCount)) * lineHeight + textInsetHeight * 2)
    }

    static func normalizedHorizontalOrigin(
        currentOrigin: CGFloat,
        documentWidth: CGFloat,
        viewportWidth: CGFloat,
        reset: Bool
    ) -> CGFloat {
        guard !reset else { return 0 }

        let maximumOrigin = max(0, documentWidth - viewportWidth)
        return min(max(0, currentOrigin), maximumOrigin)
    }
}

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
        for line in visibleLines(in: textView, layoutManager: layoutManager, textContainer: textContainer) {
            drawBackground(for: line, in: textView, layoutManager: layoutManager, textContainer: textContainer)
            drawGutter(for: line, in: textView, layoutManager: layoutManager, textContainer: textContainer)
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
        in textView: ReviewDiffTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        let color = line.backgroundColor(for: effectiveAppearance)
        guard color.alphaComponent > 0 else { return }

        color.setFill()
        for rect in visualRects(for: line, in: textView, layoutManager: layoutManager, textContainer: textContainer) {
            NSRect(x: bounds.minX, y: rect.minY, width: bounds.width, height: rect.height).fill()
        }
    }

    private func drawGutter(
        for line: ReviewDiffRenderedLine,
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

    private func visibleLines(
        in textView: ReviewDiffTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [ReviewDiffRenderedLine] {
        let visibleTextRect = textView.visibleRect
        let visibleContainerRect = NSRect(
            x: visibleTextRect.minX - textView.textContainerOrigin.x,
            y: visibleTextRect.minY - textView.textContainerOrigin.y,
            width: visibleTextRect.width,
            height: visibleTextRect.height
        )
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        return document.lines.filter { line in
            NSIntersectionRange(line.contentRange, characterRange).length > 0
                || line.contentRange.location == characterRange.location
        }
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
        for line in visibleLines(layoutManager: layoutManager, textContainer: textContainer) {
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

    private func visibleLines(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> [ReviewDiffRenderedLine] {
        let visibleContainerRect = NSRect(
            x: visibleRect.minX - textContainerOrigin.x,
            y: visibleRect.minY - textContainerOrigin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleContainerRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        return document.lines.filter { line in
            NSIntersectionRange(line.contentRange, characterRange).length > 0
                || line.contentRange.location == characterRange.location
        }
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
        let scalar = UnicodeScalar(Int(character))
        guard let scalar else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$"
    }
}

private extension ReviewDiffRenderedLine {
    init(
        kind: SourceDiffLine.Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        marker: String,
        contentRange: NSRange,
        sourceContentUTF16Length: Int,
        sourceFileURL: URL?,
        navigationSide: ReviewDiffCodeNavigationSide?,
        sourceLineNumber: Int?,
        syntaxKey: ReviewDiffLineKey?,
        fallbackSyntaxKey: ReviewDiffLineKey?
    ) {
        self.init(
            kind: Kind(kind),
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            marker: marker,
            contentRange: contentRange,
            sourceContentUTF16Length: sourceContentUTF16Length,
            sourceFileURL: sourceFileURL,
            navigationSide: navigationSide,
            sourceLineNumber: sourceLineNumber,
            syntaxKey: syntaxKey,
            fallbackSyntaxKey: fallbackSyntaxKey
        )
    }

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

private extension ReviewDiffRenderedLine.Kind {
    init(_ kind: SourceDiffLine.Kind) {
        switch kind {
        case .context:
            self = .context
        case .addition:
            self = .addition
        case .deletion:
            self = .deletion
        }
    }
}

private extension SourceDiffLine {
    var unifiedMarker: String {
        switch kind {
        case .context:
            " "
        case .addition:
            "+"
        case .deletion:
            "-"
        }
    }

    func marker(for side: ReviewDiffSyntaxSide) -> String {
        switch (kind, side) {
        case (.addition, .new):
            "+"
        case (.deletion, .old):
            "-"
        case (.context, _), (.addition, .old), (.deletion, .new):
            " "
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
        displayMode: .constant(.unified),
        wrapLines: .constant(true),
        selectBase: { _ in },
        loadRemoteBranches: { _ in },
        refresh: {},
        setHideWhitespace: { _ in },
        openFile: { _ in },
        requestCodeNavigation: { _ in },
        codeNavigationHoverRange: { _ in nil }
    )
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

    var nonEmpty: NSRange? {
        length > 0 ? self : nil
    }
}
