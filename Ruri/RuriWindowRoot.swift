//
//  RuriWindowRoot.swift
//  ruri
//

import SwiftUI

struct RuriWindowRoot: View {
    let initialProjectURL: URL?

    @Environment(\.openWindow) private var openWindow
    @StateObject private var editor = EditorState()
    @StateObject private var editorRuntimeStore = EditorRuntimeStore()
    @StateObject private var terminalState = TerminalState()
    @StateObject private var runConfigurationState = RunConfigurationState()
    @StateObject private var textSearch = ProjectTextSearchViewModel()
    @StateObject private var tabInputSettings = EditorTabInputSettingsStore()
    @StateObject private var lineWrappingSettings = EditorLineWrappingSettingsStore()
    @StateObject private var githubAuth = GitHubAuthViewModel()
    @State private var isImporterPresented = false
    @State private var isWorktreeOverviewVisible = true
    @State private var isRunConfigurationSheetPresented = false
    @State private var openedInitialProjectURL: URL?

    var body: some View {
        ContentView(
            editor: editor,
            editorRuntimeStore: editorRuntimeStore,
            terminalState: terminalState,
            runConfigurationState: runConfigurationState,
            textSearch: textSearch,
            tabInputSettings: tabInputSettings,
            lineWrappingSettings: lineWrappingSettings,
            githubAuth: githubAuth,
            isImporterPresented: $isImporterPresented,
            isWorktreeOverviewVisible: $isWorktreeOverviewVisible,
            openProjectInNewWindow: { url in
                openProjectInNewWindow(url)
            }
        )
        .navigationTitle(editor.projectName ?? "Ruri")
        .background {
            WindowAccessor { window in
                ExternalGitHubPullRequestURLRouter.shared.register(editor, window: window)
            }
            .frame(width: 0, height: 0)
        }
        .focusedSceneObject(editor)
        .focusedSceneObject(editorRuntimeStore)
        .focusedSceneObject(terminalState)
        .focusedSceneObject(runConfigurationState)
        .focusedSceneObject(textSearch)
        .focusedSceneObject(lineWrappingSettings)
        .focusedSceneValue(\.ruriOpenFolderCommandAction) {
            isImporterPresented = true
        }
        .focusedSceneValue(\.ruriToggleTerminalOverviewCommandAction) {
            toggleWorktreeOverview()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(
                    "Editor Mode",
                    selection: Binding(
                        get: { editor.editorMode },
                        set: { editor.setEditorMode($0) }
                    )
                ) {
                    Text(EditorMode.edit.displayName).tag(EditorMode.edit)
                    if editor.canUseReviewMode {
                        Text(EditorMode.review.displayName).tag(EditorMode.review)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: editor.canUseReviewMode ? 162 : 76)
                .help("Editor Mode")
            }

            ToolbarItem(placement: .navigation) {
                runToolbarControls
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await editor.refreshAllWorktreeOverview()
                    }
                } label: {
                    Label(AppText.refreshWorktreesCommand, systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(editor.projectWorkspaces.isEmpty)
                .help(AppText.refreshWorktreesCommand)
                .accessibilityLabel(AppText.refreshWorktreesCommand)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleWorktreeOverview()
                } label: {
                    Label(AppText.toggleTerminalOverviewCommand, systemImage: "sidebar.right")
                }
                .labelStyle(.iconOnly)
                .help(AppText.toggleTerminalOverviewCommand)
                .accessibilityLabel(AppText.toggleTerminalOverviewCommand)
            }
        }
        .task(id: initialProjectURL) {
            await openInitialProjectIfNeeded()
        }
        .onAppear {
            ExternalGitHubPullRequestURLRouter.shared.register(editor)
            RuriApplicationTerminationCoordinator.shared.register(editor)
        }
        .onDisappear {
            ExternalGitHubPullRequestURLRouter.shared.unregister(editor)
            RuriApplicationTerminationCoordinator.shared.unregister(editor)
        }
        .onChange(of: editor.runConfigurationMetadataLocation) { _, location in
            runConfigurationState.updateMetadataLocation(location)
        }
        .sheet(isPresented: $isRunConfigurationSheetPresented) {
            RunConfigurationSettingsView(
                configurations: runConfigurationState.configurations,
                activeConfigurationID: runConfigurationState.activeConfiguration?.id,
                save: { configurations, activeID in
                    runConfigurationState.replaceConfigurations(
                        configurations,
                        activeConfigurationID: activeID
                    )
                    isRunConfigurationSheetPresented = false
                },
                cancel: {
                    isRunConfigurationSheetPresented = false
                }
            )
        }
        .alert(
            AppText.errorTitle,
            isPresented: Binding(
                get: { runConfigurationState.currentError != nil },
                set: { if !$0 { runConfigurationState.clearError() } }
            )
        ) {
            Button(AppText.okButton) {
                runConfigurationState.clearError()
            }
        } message: {
            Text(runConfigurationState.errorMessage ?? "")
        }
    }

    private var runToolbarControls: some View {
        HStack(spacing: 2) {
            Button {
                runActiveConfiguration()
            } label: {
                Label(AppText.runCommand, systemImage: "play.fill")
            }
            .labelStyle(.iconOnly)
            .disabled(!canRunActiveConfiguration)
            .help(runMenuTitle)
            .accessibilityLabel(AppText.runCommand)

            Menu {
                if !runConfigurationState.configurations.isEmpty {
                    Picker(
                        "Active Run Configuration",
                        selection: Binding(
                            get: { runConfigurationState.activeConfiguration?.id },
                            set: { id in
                                if let id {
                                    runConfigurationState.selectConfiguration(id)
                                }
                            }
                        )
                    ) {
                        ForEach(runConfigurationState.configurations) { configuration in
                            Text(configuration.name).tag(Optional(configuration.id))
                        }
                    }

                    Divider()
                }

                Button(AppText.runConfigurationsCommand) {
                    isRunConfigurationSheetPresented = true
                }
            } label: {
                Label(AppText.runConfigurationsCommand, systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help(AppText.runConfigurationsCommand)
            .accessibilityLabel(AppText.runConfigurationsCommand)

            Button {
                terminalState.stopRunInActiveWorkspace()
            } label: {
                Label(AppText.stopCommand, systemImage: "stop.fill")
            }
            .labelStyle(.iconOnly)
            .disabled(!terminalState.canStopRunInActiveWorkspace)
            .help(AppText.stopCommand)
            .accessibilityLabel(AppText.stopCommand)
        }
    }

    private var canRunActiveConfiguration: Bool {
        runConfigurationState.canRun && terminalState.hasActiveWorkspace
    }

    private var runMenuTitle: LocalizedStringKey {
        if let configuration = runConfigurationState.activeConfiguration {
            return "Run \(configuration.name)"
        }

        return AppText.runCommand
    }

    private func runActiveConfiguration() {
        guard canRunActiveConfiguration,
              let configuration = runConfigurationState.activeConfiguration else {
            return
        }

        terminalState.run(configuration)
    }

    private func toggleWorktreeOverview() {
        setWorktreeOverviewVisible(!isWorktreeOverviewVisible)
    }

    private func setWorktreeOverviewVisible(_ isVisible: Bool) {
        guard isWorktreeOverviewVisible != isVisible else { return }
        isWorktreeOverviewVisible = isVisible
    }

    private func openInitialProjectIfNeeded() async {
        guard let url = initialProjectURL?.standardizedFileURL,
              openedInitialProjectURL != url else {
            return
        }

        openedInitialProjectURL = url
        let result = await editor.openProject(url)
        if case .requiresNewWindow(let url) = result {
            openProjectInNewWindow(url)
        }
    }

    private func openProjectInNewWindow(_ url: URL) {
        openWindow(value: ProjectWindowRequest(url: url))
    }
}
