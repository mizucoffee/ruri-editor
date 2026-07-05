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
    let expandDirectory: (URL) -> Void
    let createNode: (URL, String, Bool) -> Void
    let duplicateNode: (URL) -> Void
    let requestDelete: (FileNode) -> Void
    let notifyCopied: (String) -> Void
    let engageTreeFocus: () -> Void
    let setTreeInlineEditing: (Bool) -> Void

    @FocusState private var isTreeFocused: Bool
    @FocusState private var focusedRenameURL: URL?
    @FocusState private var isCreateFieldFocused: Bool
    @State private var renamingURL: URL?
    @State private var renamingOriginalName = ""
    @State private var renameText = ""
    @State private var creatingParentURL: URL?
    @State private var creatingIsDirectory = false
    @State private var createText = ""

    var body: some View {
        GeometryReader { geometry in
            let isHorizontalScrollEnabled = requiredContentWidth > geometry.size.width
            let scrollAxes: Axis.Set = isHorizontalScrollEnabled ? [.horizontal, .vertical] : .vertical
            let contentWidth = isHorizontalScrollEnabled ? requiredContentWidth : geometry.size.width

            ScrollViewReader { proxy in
                ScrollView(scrollAxes, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let creatingParentURL,
                           let projectURL,
                           FileURLRewriter.urlsMatch(creatingParentURL, projectURL) {
                            FileTreeCreateRow(
                                isDirectory: creatingIsDirectory,
                                level: 0,
                                rowWidth: contentWidth,
                                text: $createText,
                                isFocused: $isCreateFieldFocused,
                                commit: commitCreate,
                                cancel: cancelCreate
                            )
                        }

                        ForEach(nodes) { node in
                            FileTreeRow(
                                projectURL: projectURL,
                                node: node,
                                level: 0,
                                rowWidth: contentWidth,
                                selectedURL: selectedURL,
                                renamingURL: renamingURL,
                                creatingParentURL: creatingParentURL,
                                creatingIsDirectory: creatingIsDirectory,
                                gitSnapshot: gitSnapshot,
                                isSyntheticGitDeleted: false,
                                renameText: $renameText,
                                createText: $createText,
                                focusedRenameURL: $focusedRenameURL,
                                isCreateFieldFocused: $isCreateFieldFocused,
                                focusTree: focusTree,
                                selectNode: selectNode,
                                openFile: openFile,
                                toggleDirectory: toggleDirectory,
                                beginRename: beginRename,
                                commitRename: commitRename,
                                cancelRename: cancelRename,
                                beginCreate: beginCreate,
                                commitCreate: commitCreate,
                                cancelCreate: cancelCreate,
                                duplicateNode: duplicateNode,
                                requestDelete: requestDelete,
                                notifyCopied: notifyCopied
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
                                creatingParentURL: creatingParentURL,
                                creatingIsDirectory: creatingIsDirectory,
                                gitSnapshot: gitSnapshot,
                                isSyntheticGitDeleted: true,
                                renameText: $renameText,
                                createText: $createText,
                                focusedRenameURL: $focusedRenameURL,
                                isCreateFieldFocused: $isCreateFieldFocused,
                                focusTree: focusTree,
                                selectNode: selectNode,
                                openFile: openFile,
                                toggleDirectory: toggleDirectory,
                                beginRename: beginRename,
                                commitRename: commitRename,
                                cancelRename: cancelRename,
                                beginCreate: beginCreate,
                                commitCreate: commitCreate,
                                cancelCreate: cancelCreate,
                                duplicateNode: duplicateNode,
                                requestDelete: requestDelete,
                                notifyCopied: notifyCopied
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
            guard !isEditingInline else { return .ignored }
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !isEditingInline else { return .ignored }
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isEditingInline else { return .ignored }
            expandSelectedNode()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard !isEditingInline else { return .ignored }
            collapseSelectedNodeOrSelectParent()
            return .handled
        }
        .onKeyPress(.return) {
            guard !isEditingInline else { return .ignored }
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
        .onChange(of: isCreateFieldFocused) { oldValue, newValue in
            guard oldValue, !newValue, isCreating else { return }
            commitCreate()
        }
        .onChange(of: isTreeFocused) { _, isFocused in
            if isFocused {
                engageTreeFocus()
            }
        }
        .onChange(of: focusedRenameURL) { _, _ in
            notifyTreeInlineEditing()
        }
        .onChange(of: isCreateFieldFocused) { _, _ in
            notifyTreeInlineEditing()
        }
        .onChange(of: nodes) { _, newNodes in
            guard let creatingParentURL else { return }

            if let projectURL,
               FileURLRewriter.urlsMatch(creatingParentURL, projectURL) {
                return
            }

            guard let parentNode = findNode(at: creatingParentURL, in: newNodes),
                  parentNode.isExpanded || parentNode.isLoadingChildren else {
                cancelCreate()
                return
            }
        }
    }

    private var isRenaming: Bool {
        renamingURL != nil
    }

    private var isCreating: Bool {
        creatingParentURL != nil
    }

    private var isEditingInline: Bool {
        isRenaming || isCreating
    }

    private func focusTree() {
        guard !isEditingInline else { return }
        isTreeFocused = true
    }

    private func notifyTreeInlineEditing() {
        setTreeInlineEditing(focusedRenameURL != nil || isCreateFieldFocused)
    }

    private func beginCreate(_ node: FileNode, isDirectory: Bool) {
        let parentURL = node.isDirectory
            ? node.url
            : node.url.deletingLastPathComponent()

        if node.isDirectory {
            expandDirectory(node.url)
        }

        creatingParentURL = parentURL.standardizedFileURL
        creatingIsDirectory = isDirectory
        createText = ""
        isTreeFocused = false
    }

    private func commitCreate() {
        guard let parentURL = creatingParentURL else { return }

        let name = createText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDirectory = creatingIsDirectory
        creatingParentURL = nil
        createText = ""
        isCreateFieldFocused = false
        isTreeFocused = true

        guard !name.isEmpty else { return }

        createNode(parentURL, name, isDirectory)
    }

    private func cancelCreate() {
        creatingParentURL = nil
        createText = ""
        isCreateFieldFocused = false
        isTreeFocused = true
    }

    private func findNode(at url: URL, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if FileURLRewriter.urlsMatch(node.url, url) {
                return node
            }

            if let children = node.children,
               let match = findNode(at: url, in: children) {
                return match
            }
        }

        return nil
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
            var nextWidth = max(width, rowWidth(for: node, level: level))

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

    private func rowWidth(for node: FileNode, level: Int) -> CGFloat {
        rowWidth(
            for: node.name,
            level: level,
            includesGitBadge: node.isDirectory && gitSnapshot?.hasChangedDescendant(of: node.url) == true
        )
    }

    private func rowWidth(for name: String, level: Int) -> CGFloat {
        rowWidth(for: name, level: level, includesGitBadge: false)
    }

    private func rowWidth(for name: String, level: Int, includesGitBadge: Bool) -> CGFloat {
        let textWidth = textWidth(name)
        let indentation = CGFloat(level) * 14 + 8
        let gitBadgeWidth: CGFloat = includesGitBadge ? 14 : 0
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

// ファイルツリーの Copy Path / Copy Relative Path 表示専用の整形。パス計算は FileURLRewriter へ委譲し、
// ここでは非子孫→nil・プロジェクトroot自身→"." の表示フォールバックだけを担う。
// 検索結果の分類（SearchResultPathPolicy）とは役割が別であり、統合しない。
nonisolated enum FileTreePathFormatter {
    static func absolutePath(for url: URL) -> String {
        FileURLRewriter.normalizedPath(url)
    }

    static func relativePath(for url: URL, projectURL: URL?) -> String? {
        guard let projectURL,
              let relativePath = FileURLRewriter.relativePath(from: projectURL, to: url) else {
            return nil
        }

        return relativePath.isEmpty ? "." : relativePath
    }
}

private struct FileTreeRow: View {
    let projectURL: URL?
    let node: FileNode
    let level: Int
    let rowWidth: CGFloat
    let selectedURL: URL?
    let renamingURL: URL?
    let creatingParentURL: URL?
    let creatingIsDirectory: Bool
    let gitSnapshot: GitRepositorySnapshot?
    let isSyntheticGitDeleted: Bool
    @Binding var renameText: String
    @Binding var createText: String
    let focusedRenameURL: FocusState<URL?>.Binding
    let isCreateFieldFocused: FocusState<Bool>.Binding
    let focusTree: () -> Void
    let selectNode: (URL) -> Void
    let openFile: (URL) -> Void
    let toggleDirectory: (URL) -> Void
    let beginRename: (FileNode) -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void
    let beginCreate: (FileNode, Bool) -> Void
    let commitCreate: () -> Void
    let cancelCreate: () -> Void
    let duplicateNode: (URL) -> Void
    let requestDelete: (FileNode) -> Void
    let notifyCopied: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

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
                .overlay {
                    FileTreeRightClickCatcher(isEnabled: !isRenaming) {
                        selectOnRightClick()
                    }
                }
                .onTapGesture {
                    activateNode()
                }
                .contextMenu {
                    Button {
                        copyToPasteboard(FileTreePathFormatter.absolutePath(for: node.url))
                        notifyCopied("Path copied.")
                    } label: {
                        Label(AppText.copyPathCommand, systemImage: "doc.on.doc")
                    }

                    if let relativePath = FileTreePathFormatter.relativePath(for: node.url, projectURL: projectURL) {
                        Button {
                            copyToPasteboard(relativePath)
                            notifyCopied("Relative path copied.")
                        } label: {
                            Label(AppText.copyRelativePathCommand, systemImage: "doc.on.doc")
                        }
                    }

                    if !isSyntheticGitDeleted {
                        Divider()

                        Button {
                            beginCreate(node, false)
                        } label: {
                            Label(AppText.newFileCommand, systemImage: "doc.badge.plus")
                        }

                        Button {
                            beginCreate(node, true)
                        } label: {
                            Label(AppText.newFolderCommand, systemImage: "folder.badge.plus")
                        }

                        Divider()

                        Button {
                            beginRename(node)
                        } label: {
                            Label(AppText.renameCommand, systemImage: "pencil")
                        }

                        Button {
                            duplicateNode(node.url)
                        } label: {
                            Label(AppText.duplicateCommand, systemImage: "plus.square.on.square")
                        }

                        Divider()

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([node.url])
                        } label: {
                            Label(AppText.revealInFinderCommand, systemImage: "arrow.up.forward.app")
                        }

                        Divider()

                        Button(role: .destructive) {
                            requestDelete(node)
                        } label: {
                            Label(AppText.moveToTrashCommand, systemImage: "trash")
                        }
                    }
                }

            if node.isExpanded {
                if node.isLoadingChildren {
                    loadingRow
                } else if let children = node.children {
                    if let creatingParentURL,
                       FileURLRewriter.urlsMatch(creatingParentURL, node.url) {
                        FileTreeCreateRow(
                            isDirectory: creatingIsDirectory,
                            level: level + 1,
                            rowWidth: rowWidth,
                            text: $createText,
                            isFocused: isCreateFieldFocused,
                            commit: commitCreate,
                            cancel: cancelCreate
                        )
                    }

                    ForEach(children) { child in
                        FileTreeRow(
                            projectURL: projectURL,
                            node: child,
                            level: level + 1,
                            rowWidth: rowWidth,
                            selectedURL: selectedURL,
                            renamingURL: renamingURL,
                            creatingParentURL: creatingParentURL,
                            creatingIsDirectory: creatingIsDirectory,
                            gitSnapshot: gitSnapshot,
                            isSyntheticGitDeleted: false,
                            renameText: $renameText,
                            createText: $createText,
                            focusedRenameURL: focusedRenameURL,
                            isCreateFieldFocused: isCreateFieldFocused,
                            focusTree: focusTree,
                            selectNode: selectNode,
                            openFile: openFile,
                            toggleDirectory: toggleDirectory,
                            beginRename: beginRename,
                            commitRename: commitRename,
                            cancelRename: cancelRename,
                            beginCreate: beginCreate,
                            commitCreate: commitCreate,
                            cancelCreate: cancelCreate,
                            duplicateNode: duplicateNode,
                            requestDelete: requestDelete,
                            notifyCopied: notifyCopied
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
                            creatingParentURL: creatingParentURL,
                            creatingIsDirectory: creatingIsDirectory,
                            gitSnapshot: gitSnapshot,
                            isSyntheticGitDeleted: true,
                            renameText: $renameText,
                            createText: $createText,
                            focusedRenameURL: focusedRenameURL,
                            isCreateFieldFocused: isCreateFieldFocused,
                            focusTree: focusTree,
                            selectNode: selectNode,
                            openFile: openFile,
                            toggleDirectory: toggleDirectory,
                            beginRename: beginRename,
                            commitRename: commitRename,
                            cancelRename: cancelRename,
                            beginCreate: beginCreate,
                            commitCreate: commitCreate,
                            cancelCreate: cancelCreate,
                            duplicateNode: duplicateNode,
                            requestDelete: requestDelete,
                            notifyCopied: notifyCopied
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
        if node.isDirectory,
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

    private func selectOnRightClick() {
        guard !isSyntheticGitDeleted, !isSelected else { return }
        selectNode(node.url)
    }

    private var iconColor: Color {
        if isSyntheticGitDeleted {
            return .red
        }

        return node.isIgnored ? .secondary : .primary
    }

    private var textColor: Color {
        if !node.isDirectory,
           let status = gitChange?.displayStatus ?? (isSyntheticGitDeleted ? .deleted : nil) {
            return IntelliJFileStatusColor.color(for: status, colorScheme: colorScheme)
        }

        if node.isIgnored {
            return IntelliJFileStatusColor.ignored(colorScheme: colorScheme)
        }

        return .primary
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

// SwiftUIの.contextMenuには「メニューが開いた」ことを検知するAPIがない。ビルダーは通常の
// 再描画でも評価されるため副作用を置けず、メニュー項目のonAppearも発火しない環境がある。
// そのため右クリックをAppKitレベルで捕捉して選択を移し、イベント自体はsuperへ転送して
// コンテキストメニュー表示は既定の機構に任せる。左クリックはhitTestで素通しし、
// SwiftUI側のタップ処理やリネームTextFieldの編集メニューを妨げない。
private struct FileTreeRightClickCatcher: NSViewRepresentable {
    let isEnabled: Bool
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        CatcherView()
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onRightClick = onRightClick
    }

    final class CatcherView: NSView {
        var isEnabled = true
        var onRightClick: (() -> Void)?

        deinit {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isEnabled,
                  let hitView = super.hitTest(point),
                  hitView === self,
                  NSApp.currentEvent?.type == .rightMouseDown else {
                return nil
            }

            return self
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
            super.rightMouseDown(with: event)
        }
    }
}

private struct FileTreeCreateRow: View {
    let isDirectory: Bool
    let level: Int
    let rowWidth: CGFloat
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let commit: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 10)
                .opacity(isDirectory ? 1 : 0)

            Image(systemName: isDirectory ? "folder" : "doc.text")
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(.primary)

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1)
                .focused(isFocused)
                .onSubmit {
                    commit()
                }
                .onExitCommand {
                    cancel()
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentColor, lineWidth: 1)
                }

            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .padding(.leading, CGFloat(level) * 14 + 8)
        .padding(.trailing, 8)
        .frame(width: rowWidth, alignment: .leading)
        .onAppear {
            Task { @MainActor in
                isFocused.wrappedValue = true
            }
        }
    }
}

private enum IntelliJFileStatusColor {
    static func color(for status: GitFileDisplayStatus, colorScheme: ColorScheme) -> Color {
        let isDark = colorScheme == .dark
        switch status {
        case .modified:
            return isDark ? color(0x68, 0x97, 0xBB) : color(0x00, 0x32, 0xA0)
        case .added:
            return isDark ? color(0x62, 0x97, 0x55) : color(0x0A, 0x77, 0x00)
        case .copied:
            return color(0x0A, 0x77, 0x00)
        case .deleted:
            return isDark ? color(0x6C, 0x6C, 0x6C) : color(0x61, 0x61, 0x61)
        case .renamed:
            return isDark ? color(0x3A, 0x84, 0x84) : color(0x00, 0x7C, 0x7C)
        case .conflicted:
            return isDark ? color(0xD5, 0x75, 0x6C) : color(0xFF, 0x00, 0x00)
        case .untracked:
            return isDark ? color(0xD1, 0x67, 0x5A) : color(0x99, 0x33, 0x00)
        }
    }

    static func ignored(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? color(0x84, 0x85, 0x04) : color(0x72, 0x72, 0x38)
    }

    private static func color(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
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
        renameNode: { _, _ in },
        expandDirectory: { _ in },
        createNode: { _, _, _ in },
        duplicateNode: { _ in },
        requestDelete: { _ in },
        notifyCopied: { _ in },
        engageTreeFocus: {},
        setTreeInlineEditing: { _ in }
    )
}
