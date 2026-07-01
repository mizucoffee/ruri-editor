//
//  ContentViewSupportViews.swift
//  ruri
//

import SwiftUI

struct CodeNavigationToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
}

enum NewWorktreeSource: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: Self {
        self
    }
}

struct NewWorktreeSheet: View {
    @Binding var source: NewWorktreeSource
    @Binding var branchName: String
    @Binding var initializationCommand: String
    @Binding var remoteSearchText: String
    @Binding var selectedRemoteBranchID: GitRemoteBranchInfo.ID?
    let isCreating: Bool
    let isRetryingInitialization: Bool
    let errorMessage: String?
    let remoteBranches: [GitRemoteBranchInfo]
    let isLoadingRemoteBranches: Bool
    let remoteErrorMessage: String?
    let create: () -> Void
    let cancel: () -> Void
    let loadRemoteBranches: () -> Void

    private var trimmedBranchName: String {
        branchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRemoteSearchText: String {
        remoteSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRemoteBranches: [GitRemoteBranchInfo] {
        guard !trimmedRemoteSearchText.isEmpty else {
            return remoteBranches
        }

        return remoteBranches.filter { branch in
            branch.fullName.localizedCaseInsensitiveContains(trimmedRemoteSearchText)
                || branch.branchName.localizedCaseInsensitiveContains(trimmedRemoteSearchText)
        }
    }

    private var selectedRemoteBranch: GitRemoteBranchInfo? {
        guard let selectedRemoteBranchID else { return nil }
        return remoteBranches.first { $0.id == selectedRemoteBranchID }
    }

    private var canCreate: Bool {
        guard !isCreating else { return false }

        if isRetryingInitialization {
            return true
        }

        switch source {
        case .local:
            return !trimmedBranchName.isEmpty
        case .remote:
            return selectedRemoteBranch != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppText.newWorktreeTitle)
                .font(.headline)

            Picker("Worktree Source", selection: $source) {
                Text(AppText.newWorktreeLocalSource).tag(NewWorktreeSource.local)
                Text(AppText.newWorktreeRemoteSource).tag(NewWorktreeSource.remote)
            }
            .pickerStyle(.segmented)
            .disabled(isCreating)

            switch source {
            case .local:
                localBranchForm
            case .remote:
                remoteBranchForm
            }

            initializationForm

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button(AppText.cancelButton) {
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

                Button {
                    create()
                } label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRetryingInitialization ? AppText.retryInitializationButton : AppText.createButton)
                    }
                    .frame(minWidth: isRetryingInitialization ? 132 : 74)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if source == .remote {
                loadRemoteBranches()
            }
        }
        .onChange(of: source) { _, newSource in
            if newSource == .remote {
                loadRemoteBranches()
            }
        }
        .onChange(of: remoteSearchText) { _, _ in
            clearHiddenRemoteSelection()
        }
    }

    private var localBranchForm: some View {
        TextField(AppText.newWorktreeBranchPlaceholder, text: $branchName)
            .textFieldStyle(.roundedBorder)
            .disabled(isCreating)
            .onSubmit {
                guard canCreate else { return }
                create()
            }
    }

    private var initializationForm: some View {
        TextField(AppText.worktreeInitializationCommandPlaceholder, text: $initializationCommand)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .disabled(isCreating)
            .onSubmit {
                guard canCreate else { return }
                create()
            }
    }

    private var remoteBranchForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppText.newWorktreeRemoteSearchPlaceholder, text: $remoteSearchText)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreating || (isLoadingRemoteBranches && remoteBranches.isEmpty))

            if let remoteErrorMessage,
               !remoteErrorMessage.isEmpty,
               remoteBranches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(remoteErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(AppText.retryButton) {
                        loadRemoteBranches()
                    }
                    .disabled(isCreating || isLoadingRemoteBranches)
                }
                .frame(minHeight: 180, alignment: .center)
            } else if isLoadingRemoteBranches && remoteBranches.isEmpty {
                ProgressView(AppText.newWorktreeFetchingRemoteBranches)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if filteredRemoteBranches.isEmpty {
                ContentUnavailableView(
                    remoteBranches.isEmpty
                        ? AppText.newWorktreeNoRemoteBranches
                        : AppText.newWorktreeNoRemoteBranchMatches,
                    systemImage: "arrow.triangle.branch"
                )
                .frame(minHeight: 180)
            } else {
                List(selection: $selectedRemoteBranchID) {
                    ForEach(filteredRemoteBranches) { branch in
                        RemoteBranchRow(branch: branch)
                            .tag(branch.id)
                    }
                }
                .frame(minHeight: 180, idealHeight: 240)
                .disabled(isCreating)

                if isLoadingRemoteBranches {
                    ProgressView(AppText.newWorktreeFetchingRemoteBranches)
                        .controlSize(.small)
                }
            }
        }
    }

    private func clearHiddenRemoteSelection() {
        guard let selectedRemoteBranchID,
              !filteredRemoteBranches.contains(where: { $0.id == selectedRemoteBranchID }) else {
            return
        }

        self.selectedRemoteBranchID = nil
    }
}

private struct RemoteBranchRow: View {
    let branch: GitRemoteBranchInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.branchName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(branch.remoteName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct CodeNavigationToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: systemImage)
                .imageScale(.medium)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }
}

struct PreviewGitHubAuthService: GitHubAuthServiceProtocol {
    func currentAuthenticationStatus() async -> GitHubAuthStatusState {
        .unauthenticated
    }

    func logIn(devicePromptHandler: @escaping @Sendable (GitHubLoginDevicePrompt) -> Void) async throws {
    }
}
