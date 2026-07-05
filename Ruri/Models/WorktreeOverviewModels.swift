//
//  WorktreeOverviewModels.swift
//  ruri
//

import Foundation

struct WorktreeOverviewTerminalItem: Identifiable, Equatable, Sendable {
    let tab: TerminalTabSnapshot
    let isSelected: Bool

    var id: TerminalTab.ID {
        tab.id
    }
}

struct WorktreeOverviewItem: Identifiable, Equatable, Sendable {
    let workspace: ProjectWorkspaceSnapshot
    let branch: GitBranchState?
    let memo: String
    let pullRequestStatus: GitHubPullRequestStatus?
    let isPullRequestLoading: Bool
    let isPulling: Bool
    let terminals: [WorktreeOverviewTerminalItem]
    let isActive: Bool
    let canDelete: Bool

    var id: ProjectWorkspaceSnapshot.ID {
        workspace.id
    }

    var branchTitle: String {
        branch?.displayName ?? "No Branch"
    }

    var isBaseWorktree: Bool {
        workspace.url.lastPathComponent == "ruri-base"
    }

    var canEditMemo: Bool {
        switch branch {
        case .branch, .unborn:
            true
        case .detached, nil:
            false
        }
    }

    var copyableBranchName: String? {
        switch branch {
        case .branch(let name), .unborn(let name):
            name
        case .detached, nil:
            nil
        }
    }

    var copyablePullRequestURL: URL? {
        switch pullRequestStatus {
        case .pullRequest(let pullRequest):
            pullRequest.url
        case .create, nil:
            nil
        }
    }
}

enum WorktreeOverviewBuilder {
    static func items(
        projectWorkspaces: [ProjectWorkspaceSnapshot],
        terminalWorkspaces: [TerminalWorkspaceSnapshot],
        branchStates: [ProjectWorkspaceSnapshot.ID: GitBranchState],
        memos: [ProjectWorkspaceSnapshot.ID: String],
        pullRequestStatuses: [ProjectWorkspaceSnapshot.ID: GitHubPullRequestStatus],
        pullRequestLoadingWorkspaceIDs: Set<ProjectWorkspaceSnapshot.ID>,
        pullingWorkspaceIDs: Set<ProjectWorkspaceSnapshot.ID>,
        activeWorkspaceID: ProjectWorkspaceSnapshot.ID?,
        selectedTerminalTabID: TerminalTab.ID?,
        deletableWorkspaceIDs: Set<ProjectWorkspaceSnapshot.ID>
    ) -> [WorktreeOverviewItem] {
        let terminalWorkspacesByID = Dictionary(
            uniqueKeysWithValues: terminalWorkspaces.map { ($0.id, $0) }
        )

        return sortedWorkspaces(projectWorkspaces).map { workspace in
            let terminalWorkspace = terminalWorkspacesByID[workspace.id]
            let terminals = terminalWorkspace?.tabs.map { tab in
                WorktreeOverviewTerminalItem(
                    tab: tab,
                    isSelected: workspace.id == activeWorkspaceID && tab.id == selectedTerminalTabID
                )
            } ?? []

            return WorktreeOverviewItem(
                workspace: workspace,
                branch: branchStates[workspace.id],
                memo: memos[workspace.id] ?? "",
                pullRequestStatus: pullRequestStatuses[workspace.id],
                isPullRequestLoading: pullRequestLoadingWorkspaceIDs.contains(workspace.id),
                isPulling: pullingWorkspaceIDs.contains(workspace.id),
                terminals: terminals,
                isActive: workspace.id == activeWorkspaceID,
                canDelete: deletableWorkspaceIDs.contains(workspace.id)
            )
        }
    }

    private static func sortedWorkspaces(
        _ workspaces: [ProjectWorkspaceSnapshot]
    ) -> [ProjectWorkspaceSnapshot] {
        workspaces.enumerated()
            .sorted { first, second in
                let firstIsRuriBase = first.element.url.lastPathComponent == "ruri-base"
                let secondIsRuriBase = second.element.url.lastPathComponent == "ruri-base"

                if firstIsRuriBase != secondIsRuriBase {
                    return firstIsRuriBase
                }

                let nameComparison = first.element.displayName.localizedCaseInsensitiveCompare(
                    second.element.displayName
                )
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return first.offset < second.offset
            }
            .map(\.element)
    }
}
