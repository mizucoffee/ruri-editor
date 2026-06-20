//
//  WorktreeOverviewSidebarView.swift
//  ruri
//

import SwiftUI

struct WorktreeOverviewSidebarView: View {
    let projectWorkspaces: [ProjectWorkspaceSnapshot]
    let terminalWorkspaces: [TerminalWorkspaceSnapshot]
    let branchStates: [ProjectWorkspaceSnapshot.ID: GitBranchState]
    let memos: [ProjectWorkspaceSnapshot.ID: String]
    let pullRequestStatuses: [ProjectWorkspaceSnapshot.ID: GitHubPullRequestStatus]
    let pullRequestLoadingWorkspaceIDs: Set<ProjectWorkspaceSnapshot.ID>
    let activeWorkspaceID: ProjectWorkspaceSnapshot.ID?
    let selectedTerminalTabID: TerminalTab.ID?
    let deletableWorkspaceIDs: Set<ProjectWorkspaceSnapshot.ID>
    let canCreateWorktree: Bool
    let selectProject: (ProjectWorkspaceSnapshot.ID) -> Void
    let selectTerminal: (ProjectWorkspaceSnapshot.ID, TerminalTab.ID) -> Void
    let updateMemo: (ProjectWorkspaceSnapshot.ID, String) -> Void
    let createWorktree: () -> Void
    let deleteWorktree: (ProjectWorkspaceSnapshot.ID) -> Void
    let pullWorktree: (ProjectWorkspaceSnapshot.ID) -> Void
    let openPullRequest: (URL) -> Void

    private var items: [WorktreeOverviewItem] {
        WorktreeOverviewBuilder.items(
            projectWorkspaces: projectWorkspaces,
            terminalWorkspaces: terminalWorkspaces,
            branchStates: branchStates,
            memos: memos,
            pullRequestStatuses: pullRequestStatuses,
            pullRequestLoadingWorkspaceIDs: pullRequestLoadingWorkspaceIDs,
            activeWorkspaceID: activeWorkspaceID,
            selectedTerminalTabID: selectedTerminalTabID,
            deletableWorkspaceIDs: deletableWorkspaceIDs
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    AppText.noWorktreesTitle,
                    systemImage: "folder.badge.gearshape",
                    description: Text(AppText.noWorktreesDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { item in
                            overviewCard(item)
                        }
                    }
                    .padding(10)
                }
            }

            Divider()

            Button {
                createWorktree()
            } label: {
                Label(AppText.newWorktreeCommand, systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canCreateWorktree)
            .padding(10)
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360, maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tree")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(AppText.worktreeOverviewTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func overviewCard(_ item: WorktreeOverviewItem) -> some View {
        if item.isBaseWorktree {
            BaseWorktreeOverviewCard(
                item: item,
                isActive: item.isActive,
                selectProject: {
                    selectProject(item.id)
                },
                pullWorktree: {
                    pullWorktree(item.id)
                },
                selectTerminal: { terminalID in
                    selectTerminal(item.id, terminalID)
                }
            )
        } else {
            LinkedWorktreeOverviewCard(
                item: item,
                memoText: memos[item.id] ?? item.memo,
                isActive: item.isActive,
                selectProject: {
                    selectProject(item.id)
                },
                updateMemo: { memo in
                    updateMemo(item.id, memo)
                },
                deleteWorktree: item.canDelete ? {
                    deleteWorktree(item.id)
                } : nil,
                openPullRequest: openPullRequest,
                selectTerminal: { terminalID in
                    selectTerminal(item.id, terminalID)
                }
            )
        }
    }
}
