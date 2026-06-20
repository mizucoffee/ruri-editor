//
//  ProjectSidebarView.swift
//  ruri
//

import SwiftUI

struct ProjectSidebarView: View {
    let projectWorkspaces: [ProjectWorkspaceSnapshot]
    let activeProjectID: ProjectWorkspaceSnapshot.ID?
    let projectURL: URL?
    let fileTree: [FileNode]
    let selectedFileTreeURL: URL?
    let gitSnapshot: GitRepositorySnapshot?
    let isFileTreeShowingChangedFilesOnly: Bool
    let canShowChangedFilesOnlyInFileTree: Bool
    let canFocusSelectedFileInTree: Bool
    let selectFileTreeNode: (URL) -> Void
    let toggleFileTreeChangedFilesOnly: () -> Void
    let focusSelectedFileInTree: () -> Void
    let openFile: (URL) -> Void
    let toggleDirectory: (URL) -> Void
    let moveFileTreeSelection: (Int) -> Void
    let expandSelectedFileTreeNode: () -> Void
    let collapseSelectedFileTreeNodeOrSelectParent: () -> Void
    let activateSelectedFileTreeNode: () -> Void
    let renameFileTreeNode: (URL, String) -> Void

    private var activeProject: ProjectWorkspaceSnapshot? {
        guard let activeProjectID else { return nil }
        return projectWorkspaces.first { $0.id == activeProjectID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeProject != nil {
                projectHeader

                Divider()

                FileTreeView(
                    projectURL: activeProject?.url,
                    nodes: fileTree,
                    selectedURL: selectedFileTreeURL,
                    gitSnapshot: gitSnapshot,
                    selectNode: selectFileTreeNode,
                    openFile: openFile,
                    toggleDirectory: toggleDirectory,
                    moveSelection: moveFileTreeSelection,
                    expandSelectedNode: expandSelectedFileTreeNode,
                    collapseSelectedNodeOrSelectParent: collapseSelectedFileTreeNodeOrSelectParent,
                    activateSelectedNode: activateSelectedFileTreeNode,
                    renameNode: renameFileTreeNode
                )
            } else {
                ContentUnavailableView(
                    AppText.noFolderOpenedTitle,
                    systemImage: "folder",
                    description: Text(AppText.openFolderDescription)
                )
            }
        }
    }

    private var projectHeader: some View {
        HStack(spacing: 6) {
            projectTitle
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                toggleFileTreeChangedFilesOnly()
            } label: {
                Image(systemName: isFileTreeShowingChangedFilesOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canShowChangedFilesOnlyInFileTree)
            .foregroundStyle(isFileTreeShowingChangedFilesOnly ? Color.accentColor : Color.primary)
            .help(AppText.showChangedFilesOnlyInTreeCommand)
            .accessibilityLabel(AppText.showChangedFilesOnlyInTreeCommand)

            Button {
                focusSelectedFileInTree()
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canFocusSelectedFileInTree)
            .help(AppText.focusCurrentFileInTreeCommand)
            .accessibilityLabel(AppText.focusCurrentFileInTreeCommand)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var projectTitle: some View {
        projectLabel()
    }

    private func projectLabel() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(activeProject?.displayName ?? projectURL?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let displayPath = activeProject?.displayPath {
                    Text(displayPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

        }
        .contentShape(Rectangle())
    }
}

#Preview {
    let projectURL = URL(filePath: "/tmp/ruri")

    ProjectSidebarView(
        projectWorkspaces: [
            ProjectWorkspaceSnapshot(id: projectURL, url: projectURL)
        ],
        activeProjectID: projectURL,
        projectURL: projectURL,
        fileTree: [
            FileNode(
                url: URL(filePath: "/tmp/ruri/Sources"),
                name: "Sources",
                isDirectory: true,
                children: [
                    FileNode(
                        url: URL(filePath: "/tmp/ruri/Sources/App.swift"),
                        name: "App.swift",
                        isDirectory: false
                    )
                ]
            )
        ],
        selectedFileTreeURL: URL(filePath: "/tmp/ruri/Sources"),
        gitSnapshot: nil,
        isFileTreeShowingChangedFilesOnly: false,
        canShowChangedFilesOnlyInFileTree: false,
        canFocusSelectedFileInTree: true,
        selectFileTreeNode: { _ in },
        toggleFileTreeChangedFilesOnly: {},
        focusSelectedFileInTree: {},
        openFile: { _ in },
        toggleDirectory: { _ in },
        moveFileTreeSelection: { _ in },
        expandSelectedFileTreeNode: {},
        collapseSelectedFileTreeNodeOrSelectParent: {},
        activateSelectedFileTreeNode: {},
        renameFileTreeNode: { _, _ in }
    )
}
