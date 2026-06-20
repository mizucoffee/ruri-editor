//
//  FileTreeView.swift
//  ruri
//

import AppKit
import SwiftUI

struct FileTreeView: View {
    let projectURL: URL?
    let nodes: [FileNode]
    let selectedURL: URL?
    let gitSnapshot: GitRepositorySnapshot?
    let selectNode: (URL) -> Void
    let openFile: (URL) -> Void
    let toggleDirectory: (URL) -> Void
    let moveSelection: (Int) -> Void
    let expandSelectedNode: () -> Void
    let collapseSelectedNodeOrSelectParent: () -> Void
    let activateSelectedNode: () -> Void
    let renameNode: (URL, String) -> Void

    @FocusState private var isTreeFocused: Bool
    @FocusState private var focusedRenameURL: URL?
    @State private var renamingURL: URL?
    @State private var renamingOriginalName = ""
    @State private var renameText = ""

    var body: some View {
        GeometryReader { geometry in
            let isHorizontalScrollEnabled = requiredContentWidth > geometry.size.width
            let scrollAxes: Axis.Set = isHorizontalScrollEnabled ? [.horizontal, .vertical] : .vertical
            let contentWidth = isHorizontalScrollEnabled ? requiredContentWidth : geometry.size.width

            ScrollViewReader { proxy in
                ScrollView(scrollAxes, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(nodes) { node in
                            FileTreeRow(
                                projectURL: projectURL,
                                node: node,
                                level: 0,
                                rowWidth: contentWidth,
                                selectedURL: selectedURL,
                                renamingURL: renamingURL,
                                gitSnapshot: gitSnapshot,
                                isSyntheticGitDeleted: false,
                                renameText: $renameText,
                                focusedRenameURL: $focusedRenameURL,
                                focusTree: focusTree,
                                selectNode: selectNode,
                                openFile: openFile,
                                toggleDirectory: toggleDirectory,
                                beginRename: beginRename,
                                commitRename: commitRename,
                                cancelRename: cancelRename
                            )
                        }

                        ForEach(rootDeletedChanges, id: \.url) { change in
                            FileTreeRow(
                                projectURL: projectURL,
                                node: deletedNode(for: change),
                                level: 0,
                                rowWidth: contentWidth,
                                selectedURL: selectedURL,
                                renamingURL: renamingURL,
                                gitSnapshot: gitSnapshot,
                                isSyntheticGitDeleted: true,
                                renameText: $renameText,
                                focusedRenameURL: $focusedRenameURL,
                                focusTree: focusTree,
                                selectNode: selectNode,
                                openFile: openFile,
                                toggleDirectory: toggleDirectory,
                                beginRename: beginRename,
                                commitRename: commitRename,
                                cancelRename: cancelRename
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(width: contentWidth, alignment: .topLeading)
                    .frame(minHeight: geometry.size.height, alignment: .topLeading)
                }
                .id(isHorizontalScrollEnabled)
                .contentShape(Rectangle())
                .onTapGesture {
                    focusTree()
                }
                .onChange(of: selectedURL) { _, newValue in
                    guard let newValue else { return }

                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue)
                    }
                }
            }
        }
        .focusable()
        .focused($isTreeFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            guard !isRenaming else { return .ignored }
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !isRenaming else { return .ignored }
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isRenaming else { return .ignored }
            expandSelectedNode()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isRenaming else { return .ignored }
            collapseSelectedNodeOrSelectParent()
            return .handled
        }
        .onKeyPress(.return) {
            guard !isRenaming else { return .ignored }
            activateSelectedNode()
            return .handled
        }
        .onChange(of: focusedRenameURL) { oldValue, newValue in
            guard let oldValue,
                  oldValue == renamingURL,
                  newValue != oldValue else {
                return
            }

            commitRename()
        }
    }

    private var isRenaming: Bool {
        renamingURL != nil
    }

    private func focusTree() {
        guard !isRenaming else { return }
        isTreeFocused = true
    }

    private func beginRename(_ node: FileNode) {
        selectNode(node.url)
        renamingURL = node.url
        renamingOriginalName = node.name
        renameText = node.name
        isTreeFocused = false

        Task { @MainActor in
            focusedRenameURL = node.url
        }
    }

    private func commitRename() {
        guard let renamingURL else { return }

        let proposedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = renamingOriginalName
        self.renamingURL = nil
        renamingOriginalName = ""
        renameText = ""
        focusedRenameURL = nil
        isTreeFocused = true

        guard !proposedName.isEmpty,
              proposedName != originalName else {
            return
        }

        renameNode(renamingURL, proposedName)
    }

    private func cancelRename() {
        renamingURL = nil
        renamingOriginalName = ""
        renameText = ""
        focusedRenameURL = nil
        isTreeFocused = true
    }

    private var requiredContentWidth: CGFloat {
        maxContentWidth(in: nodes, level: 0)
    }

    private func maxContentWidth(in nodes: [FileNode], level: Int) -> CGFloat {
        var width = nodes.reduce(0) { width, node in
            var nextWidth = max(width, rowWidth(for: node.name, level: level))

            if node.isExpanded {
                if node.isLoadingChildren {
                    nextWidth = max(nextWidth, loadingRowWidth(level: level + 1))
                } else if let children = node.children {
                    nextWidth = max(nextWidth, maxContentWidth(in: children, level: level + 1))
                    let deletedWidths = deletedChanges(
                        in: node.url,
                        existingNodes: children
                    ).map { rowWidth(for: $0.url.lastPathComponent, level: level + 1) }
                    nextWidth = max(nextWidth, deletedWidths.max() ?? 0)
                }
            }

            return nextWidth
        }

        if level == 0 {
            width = max(width, rootDeletedChanges.map { rowWidth(for: $0.url.lastPathComponent, level: 0) }.max() ?? 0)
        }

        return width
    }

    private func rowWidth(for name: String, level: Int) -> CGFloat {
        let textWidth = textWidth(name)
        let indentation = CGFloat(level) * 14 + 8
        let gitBadgeWidth: CGFloat = gitSnapshot == nil ? 0 : 20
        let rowChromeWidth: CGFloat = 10 + 14 + 15 + 8 + gitBadgeWidth
        return indentation + rowChromeWidth + textWidth + 16
    }

    private func loadingRowWidth(level: Int) -> CGFloat {
        let indentation = CGFloat(level) * 14 + 8
        let rowChromeWidth: CGFloat = 16 + 6 + 8
        return indentation + rowChromeWidth + textWidth("Loading")
    }

    private func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width)
    }

    private var rootDeletedChanges: [GitFileChange] {
        guard let projectURL else { return [] }
        return deletedChanges(in: projectURL, existingNodes: nodes)
    }

    private func deletedChanges(in directoryURL: URL, existingNodes: [FileNode]) -> [GitFileChange] {
        gitSnapshot?.deletedChanges(
            in: directoryURL,
            excluding: Set(existingNodes.map(\.url))
        ) ?? []
    }

    private func deletedNode(for change: GitFileChange) -> FileNode {
        FileNode(
            url: change.url,
            name: change.url.lastPathComponent,
            isDirectory: false
        )
    }
}

nonisolated enum FileTreePathFormatter {
    static func absolutePath(for url: URL) -> String {
        FileURLRewriter.normalizedPath(url)
    }

    static func relativePath(for url: URL, projectURL: URL?) -> String? {
        guard let projectURL else { return nil }

        let path = FileURLRewriter.normalizedPath(url)
        let rootPath = FileURLRewriter.normalizedPath(projectURL)

        if path == rootPath {
            return "."
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard path.hasPrefix(rootPrefix) else {
            return nil
        }

        return String(path.dropFirst(rootPrefix.count))
    }
}

private struct FileTreeRow: View {
    let projectURL: URL?
    let node: FileNode
    let level: Int
    let rowWidth: CGFloat
    let selectedURL: URL?
    let renamingURL: URL?
    let gitSnapshot: GitRepositorySnapshot?
    let isSyntheticGitDeleted: Bool
    @Binding var renameText: String
    let focusedRenameURL: FocusState<URL?>.Binding
    let focusTree: () -> Void
    let selectNode: (URL) -> Void
    let openFile: (URL) -> Void
    let toggleDirectory: (URL) -> Void
    let beginRename: (FileNode) -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
                .id(node.url)
                .frame(height: 20)
                .padding(.leading, CGFloat(level) * 14 + 8)
                .padding(.trailing, 8)
                .frame(width: rowWidth, alignment: .leading)
                .contentShape(Rectangle())
                .background(selectionBackground)
                .onTapGesture {
                    activateNode()
                }
                .contextMenu {
                    Button {
                        copyToPasteboard(FileTreePathFormatter.absolutePath(for: node.url))
                    } label: {
                        Label(AppText.copyPathCommand, systemImage: "doc.on.doc")
                    }

                    if let relativePath = FileTreePathFormatter.relativePath(for: node.url, projectURL: projectURL) {
                        Button {
                            copyToPasteboard(relativePath)
                        } label: {
                            Label(AppText.copyRelativePathCommand, systemImage: "doc.on.doc")
                        }
                    }

                    if !isSyntheticGitDeleted {
                        Divider()

                        Button {
                            beginRename(node)
                        } label: {
                            Label(AppText.renameCommand, systemImage: "pencil")
                        }
                    }
                }

            if node.isExpanded {
                if node.isLoadingChildren {
                    loadingRow
                } else if let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(
                            projectURL: projectURL,
                            node: child,
                            level: level + 1,
                            rowWidth: rowWidth,
                            selectedURL: selectedURL,
                            renamingURL: renamingURL,
                            gitSnapshot: gitSnapshot,
                            isSyntheticGitDeleted: false,
                            renameText: $renameText,
                            focusedRenameURL: focusedRenameURL,
                            focusTree: focusTree,
                            selectNode: selectNode,
                            openFile: openFile,
                            toggleDirectory: toggleDirectory,
                            beginRename: beginRename,
                            commitRename: commitRename,
                            cancelRename: cancelRename
                        )
                    }

                    ForEach(deletedChangesInDirectory, id: \.url) { change in
                        FileTreeRow(
                            projectURL: projectURL,
                            node: deletedNode(for: change),
                            level: level + 1,
                            rowWidth: rowWidth,
                            selectedURL: selectedURL,
                            renamingURL: renamingURL,
                            gitSnapshot: gitSnapshot,
                            isSyntheticGitDeleted: true,
                            renameText: $renameText,
                            focusedRenameURL: focusedRenameURL,
                            focusTree: focusTree,
                            selectNode: selectNode,
                            openFile: openFile,
                            toggleDirectory: toggleDirectory,
                            beginRename: beginRename,
                            commitRename: commitRename,
                            cancelRename: cancelRename
                        )
                    }
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 5) {
            Image(systemName: disclosureImageName)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 10)
                .opacity(node.isDirectory ? 1 : 0)

            Image(systemName: node.systemImage)
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(iconColor)

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .focused(focusedRenameURL, equals: node.url)
                    .onSubmit {
                        commitRename()
                    }
                    .onExitCommand {
                        cancelRename()
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.accentColor, lineWidth: 1)
                    }
            } else {
                Text(node.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(textColor)
                    .strikethrough(isSyntheticGitDeleted || gitChange?.isDeleted == true)
                    .layoutPriority(1)
            }

            if !isRenaming {
                gitBadge
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var gitBadge: some View {
        if let status = gitChange?.displayStatus ?? (isSyntheticGitDeleted ? .deleted : nil) {
            GitFileTreeStatusBadge(status: status)
        } else if node.isDirectory,
                  gitSnapshot?.hasChangedDescendant(of: node.url) == true {
            Image(systemName: "circle.fill")
                .font(.system(size: 5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.22))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
        }
    }

    private var isSelected: Bool {
        selectedURL == node.url
    }

    private var isRenaming: Bool {
        renamingURL == node.url
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var iconColor: Color {
        if isSyntheticGitDeleted {
            return .red
        }

        return node.isIgnored ? .secondary : .primary
    }

    private var textColor: Color {
        isSyntheticGitDeleted || node.isIgnored ? .secondary : .primary
    }

    private func activateNode() {
        guard !isRenaming,
              !isSyntheticGitDeleted else {
            return
        }

        focusTree()
        selectNode(node.url)

        if node.isDirectory {
            toggleDirectory(node.url)
        } else {
            openFile(node.url)
        }
    }

    private var disclosureImageName: String {
        node.isExpanded ? "chevron.down" : "chevron.right"
    }

    private var gitChange: GitFileChange? {
        gitSnapshot?.change(for: node.url)
    }

    private var deletedChangesInDirectory: [GitFileChange] {
        guard node.isDirectory,
              let children = node.children else {
            return []
        }

        return gitSnapshot?.deletedChanges(
            in: node.url,
            excluding: Set(children.map(\.url))
        ) ?? []
    }

    private func deletedNode(for change: GitFileChange) -> FileNode {
        FileNode(
            url: change.url,
            name: change.url.lastPathComponent,
            isDirectory: false
        )
    }

    private var loadingRow: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)

            Text(AppText.loading)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .padding(.leading, CGFloat(level + 1) * 14 + 8)
        .padding(.trailing, 8)
        .frame(width: rowWidth, alignment: .leading)
    }
}

private struct GitFileTreeStatusBadge: View {
    let status: GitFileDisplayStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: 14, alignment: .trailing)
            .help(status.description)
    }

    private var color: Color {
        switch status {
        case .modified:
            .orange
        case .added, .copied:
            .green
        case .deleted:
            .red
        case .renamed:
            .blue
        case .conflicted:
            .red
        case .untracked:
            .secondary
        }
    }
}

#Preview {
    FileTreeView(
        projectURL: URL(filePath: "/tmp/ruri"),
        nodes: [
            FileNode(
                url: URL(filePath: "/tmp/ruri/Sources"),
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(
                        url: URL(filePath: "/tmp/ruri/Sources/App.swift"),
                        name: "App.swift",
                        isDirectory: false
                    ),
                    FileNode(
                        url: URL(filePath: "/tmp/ruri/Sources/ExtremelyLongFileNameThatShouldRemainFullyVisibleByHorizontalScrollingInsteadOfMiddleTruncation.swift"),
                        name: "ExtremelyLongFileNameThatShouldRemainFullyVisibleByHorizontalScrollingInsteadOfMiddleTruncation.swift",
                        isDirectory: false
                    )
                ],
                isExpanded: true
            )
        ],
        selectedURL: URL(filePath: "/tmp/ruri/Sources"),
        gitSnapshot: nil,
        selectNode: { _ in },
        openFile: { _ in },
        toggleDirectory: { _ in },
        moveSelection: { _ in },
        expandSelectedNode: {},
        collapseSelectedNodeOrSelectParent: {},
        activateSelectedNode: {},
        renameNode: { _, _ in }
    )
}
