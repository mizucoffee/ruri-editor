//
//  WorktreeOverviewCards.swift
//  ruri
//

import SwiftUI

struct BaseWorktreeOverviewCard: View {
    let item: WorktreeOverviewItem
    let isActive: Bool
    let selectProject: () -> Void
    let pullWorktree: () -> Void
    let selectTerminal: (TerminalTab.ID) -> Void
    let notifyCopied: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                    Image(systemName: isActive ? "checkmark.circle.fill" : "folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                }
                .frame(width: 28, height: 28)

                HStack(spacing: 6) {
                    Text(item.branchTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("RURI-BASE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.12))
                        }
                }

                Spacer(minLength: 0)

                Button {
                    pullWorktree()
                } label: {
                    Group {
                        if item.isPulling {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.isPulling)
                .help(AppText.pullWorktreeCommand)
                .accessibilityLabel(AppText.pullWorktreeCommand)
            }

            WorktreeOverviewTerminalList(
                item: item,
                selectTerminal: selectTerminal
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.16))
        }
        .onTapGesture(perform: selectProject)
        .contextMenu {
            worktreeCardContextMenuItems(for: item, notifyCopied: notifyCopied)
        }
        .help(item.workspace.displayPath)
    }
}

struct LinkedWorktreeOverviewCard: View {
    let item: WorktreeOverviewItem
    let memoText: String
    let isActive: Bool
    let selectProject: () -> Void
    let updateMemo: (String) -> Void
    let deleteWorktree: (() -> Void)?
    let openPullRequest: (URL) -> Void
    let selectTerminal: (TerminalTab.ID) -> Void
    let notifyCopied: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            memoView
            WorktreeOverviewTerminalList(
                item: item,
                selectTerminal: selectTerminal
            )
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.16))
        }
        .onTapGesture(perform: selectProject)
        .contextMenu {
            worktreeCardContextMenuItems(for: item, notifyCopied: notifyCopied)
        }
        .help(item.workspace.displayPath)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                Image(systemName: isActive ? "checkmark.circle.fill" : "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.branchTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                pullRequestDetail
            }

            Spacer(minLength: 0)

            if let deleteWorktree {
                Button(role: .destructive) {
                    deleteWorktree()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(AppText.deleteWorktreeCommand)
                .accessibilityLabel(AppText.deleteWorktreeCommand)
            }
        }
    }

    @ViewBuilder
    private var pullRequestDetail: some View {
        if item.isPullRequestLoading {
            Text("Loading PR...")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else {
            switch item.pullRequestStatus {
            case .pullRequest(let pullRequest):
                Button {
                    openPullRequest(pullRequest.url)
                } label: {
                    HStack(spacing: 4) {
                        Text(pullRequest.displayTitle)
                            .font(.caption2)
                            .lineLimit(1)

                        if pullRequest.isDraft {
                            Text("Draft")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(GitHubPullRequestStatusColor.draft)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background {
                                    Capsule()
                                        .fill(GitHubPullRequestStatusColor.draft.opacity(0.12))
                                }
                        }

                        if pullRequest.showsConflicts {
                            Text("Conflicts")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(GitHubPullRequestStatusColor.closed)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background {
                                    Capsule()
                                        .fill(GitHubPullRequestStatusColor.closed.opacity(0.12))
                                }
                        }

                        GitHubPullRequestLifecycleMark(state: pullRequest.lifecycleState)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Pull request \(pullRequest.displayTitle), \(pullRequest.displayStateDescription)")
                .accessibilityLabel("Pull request \(pullRequest.displayTitle), \(pullRequest.displayStateDescription)")

            case .create(let link):
                Button {
                    openPullRequest(link.url)
                } label: {
                    Text("No PR")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            case nil:
                Text("No PR")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var memoView: some View {
        if item.canEditMemo {
            TextField(
                AppText.worktreeMemoPlaceholder,
                text: Binding(
                    get: { memoText },
                    set: updateMemo
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.caption)
            .lineLimit(1...3)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
            }
        }
    }
}

@ViewBuilder
private func worktreeCardContextMenuItems(
    for item: WorktreeOverviewItem,
    notifyCopied: @escaping (String) -> Void
) -> some View {
    if let branchName = item.copyableBranchName {
        Button {
            copyToPasteboard(branchName)
            notifyCopied("Branch name copied.")
        } label: {
            Label(AppText.copyBranchNameCommand, systemImage: "doc.on.doc")
        }
    }
    if let url = item.copyablePullRequestURL {
        Button {
            copyToPasteboard(url.absoluteString)
            notifyCopied("Pull request URL copied.")
        } label: {
            Label(AppText.copyPullRequestURLCommand, systemImage: "link")
        }
    }
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

private struct GitHubPullRequestLifecycleMark: View {
    let state: GitHubPullRequestLifecycleState

    var body: some View {
        Image(systemName: systemImageName)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var systemImageName: String {
        switch state {
        case .open:
            "circle.fill"
        case .closed:
            "xmark.circle.fill"
        case .merged:
            "checkmark.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .open:
            GitHubPullRequestStatusColor.open
        case .closed:
            GitHubPullRequestStatusColor.closed
        case .merged:
            GitHubPullRequestStatusColor.merged
        case .unknown:
            .secondary
        }
    }
}

private enum GitHubPullRequestStatusColor {
    static let open = Color(red: Double(0x1f) / 255.0, green: Double(0x88) / 255.0, blue: Double(0x3d) / 255.0)
    static let merged = Color(red: Double(0x82) / 255.0, green: Double(0x50) / 255.0, blue: Double(0xdf) / 255.0)
    static let draft = Color(red: Double(0x65) / 255.0, green: Double(0x6c) / 255.0, blue: Double(0x76) / 255.0)
    static let closed = Color(red: Double(0xc9) / 255.0, green: Double(0x3c) / 255.0, blue: Double(0x37) / 255.0)
}

private struct WorktreeOverviewTerminalList: View {
    let item: WorktreeOverviewItem
    let selectTerminal: (TerminalTab.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                Text("Terminal List")
                    .font(.caption2)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Text("\(item.terminals.count)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)

            if item.terminals.isEmpty {
                Text("No terminals")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                ForEach(item.terminals) { terminal in
                    terminalRow(terminal)
                }
            }
        }
    }

    private func terminalRow(_ terminal: WorktreeOverviewTerminalItem) -> some View {
        Button {
            selectTerminal(terminal.id)
        } label: {
            HStack(spacing: 7) {
                if let agentStatus = terminal.tab.agentStatus {
                    CodingAgentStatusIndicator(agentStatus: agentStatus)
                }

                Text(terminal.tab.title)
                    .font(.system(size: 12, weight: terminal.isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(terminal.isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        }
    }
}

private struct CodingAgentStatusIndicator: View {
    let agentStatus: CodingAgentTerminalStatus

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch agentStatus.status.state {
            case .running:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            case .waiting:
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(Color.orange)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.secondary)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.red)
            }

            if agentStatus.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: -2)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 14, height: 14)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        "\(agentStatus.status.displayTitle) \(agentStatus.status.state.rawValue) at \(agentStatus.status.event)"
    }
}
