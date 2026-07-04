//
//  AppCommands.swift
//  ruri
//

import AppKit
import SwiftUI

struct AppCommands: Commands {
    @FocusedObject private var editor: EditorViewModel?
    @FocusedObject private var editorRuntimeStore: EditorRuntimeStore?
    @FocusedObject private var terminalState: TerminalViewModel?
    @FocusedObject private var runConfigurationState: RunConfigurationViewModel?
    @FocusedObject private var textSearch: ProjectTextSearchViewModel?
    @FocusedObject private var lineWrappingSettings: EditorLineWrappingSettingsStore?
    @FocusedValue(\.ruriOpenFolderCommandAction) private var openFolderCommandAction
    @FocusedValue(\.ruriToggleTerminalOverviewCommandAction) private var toggleTerminalOverviewCommandAction

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(AppText.aboutCommand) {
                showAboutPanel()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button(AppText.openFolderCommand) {
                openFolderCommandAction?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openFolderCommandAction == nil)

            Button(AppText.closeTabCommand) {
                closeCommandTarget()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Divider()

            Button(AppText.selectLastTabCommand) {
                editor?.selectTab(atShortcutNumber: 0)
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab1Command) {
                editor?.selectTab(atShortcutNumber: 1)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab2Command) {
                editor?.selectTab(atShortcutNumber: 2)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab3Command) {
                editor?.selectTab(atShortcutNumber: 3)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab4Command) {
                editor?.selectTab(atShortcutNumber: 4)
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab5Command) {
                editor?.selectTab(atShortcutNumber: 5)
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab6Command) {
                editor?.selectTab(atShortcutNumber: 6)
            }
            .keyboardShortcut("6", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab7Command) {
                editor?.selectTab(atShortcutNumber: 7)
            }
            .keyboardShortcut("7", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab8Command) {
                editor?.selectTab(atShortcutNumber: 8)
            }
            .keyboardShortcut("8", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)

            Button(AppText.selectTab9Command) {
                editor?.selectTab(atShortcutNumber: 9)
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(editor?.canCloseCommandTarget != true || editorRuntimeStore == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button(AppText.saveCommand) {
                Task {
                    await editor?.saveCommandTarget()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(editor?.canSaveCommandTarget != true)
        }

        CommandMenu(AppText.navigationCommandMenu) {
            Button(AppText.navigateBackCommand) {
                Task {
                    await editor?.navigateBackInHistory()
                }
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(editor?.canNavigateBack != true)

            Button(AppText.navigateForwardCommand) {
                Task {
                    await editor?.navigateForwardInHistory()
                }
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(editor?.canNavigateForward != true)
        }

        CommandMenu(AppText.searchCommandMenu) {
            Button(AppText.goToImplementationCommand) {
                editorRuntimeStore?.goToImplementation()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(editor?.selectedTabID == nil || editorRuntimeStore == nil)

            Divider()

            Button(AppText.findCommand) {
                editorRuntimeStore?.presentFind(showsReplace: false)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(editor?.selectedTabID == nil || editorRuntimeStore == nil)

            Button(AppText.findAndReplaceCommand) {
                editorRuntimeStore?.presentFind(showsReplace: true)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(editor?.selectedTabID == nil || editorRuntimeStore == nil)

            Divider()

            Button(AppText.findInFilesCommand) {
                textSearch?.present(projectURL: editor?.projectURL)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(editor?.projectURL == nil || textSearch == nil)
        }

        CommandMenu(AppText.editorCommandMenu) {
            Toggle(
                AppText.lineWrapCommand,
                isOn: Binding(
                    get: {
                        lineWrappingSettings?.mode.isWrappingEnabled ?? true
                    },
                    set: { isEnabled in
                        lineWrappingSettings?.setWrappingEnabled(isEnabled)
                    }
                )
            )
            .disabled(lineWrappingSettings == nil)
        }

        CommandMenu(AppText.terminalCommandMenu) {
            Button(AppText.toggleTerminalCommand) {
                terminalState?.toggleMinimized()
            }
            .keyboardShortcut("j", modifiers: .command)
            .disabled(terminalState?.hasActiveWorkspace != true)

            Button(AppText.newTerminalTabCommand) {
                terminalState?.createTab()
            }
            .disabled(terminalState?.hasActiveWorkspace != true)

            Divider()

            Button(AppText.toggleTerminalOverviewCommand) {
                toggleTerminalOverviewCommandAction?()
            }
            .keyboardShortcut("j", modifiers: [.command, .option])
            .disabled(toggleTerminalOverviewCommandAction == nil)
        }

        CommandMenu(AppText.runCommandMenu) {
            Button(AppText.runCommand) {
                if let configuration = runConfigurationState?.activeConfiguration {
                    terminalState?.run(configuration)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(runConfigurationState?.canRun != true || terminalState?.hasActiveWorkspace != true)

            Button(AppText.stopCommand) {
                terminalState?.stopRunInActiveWorkspace()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(terminalState?.canStopRunInActiveWorkspace != true)
        }
    }

    private func closeCommandTarget() {
        guard let editor,
              let editorRuntimeStore,
              let closedDocument = editor.closeCommandTarget() else {
            return
        }

        editorRuntimeStore.closeDocument(
            workspaceID: closedDocument.workspaceID,
            documentID: closedDocument.documentID
        )
    }

    private func showAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                .applicationVersion: AppMetadata.aboutVersionText
            ]
        )
    }
}

private enum AppMetadata {
    static var aboutVersionText: String {
        let version = bundleString(for: "CFBundleShortVersionString") ?? "1.0"
        let commitShortHash = bundleString(for: "RuriGitCommitShortHash")

        guard let commitShortHash,
              !commitShortHash.isEmpty,
              commitShortHash != "$(RURI_GIT_COMMIT_SHORT_HASH)" else {
            return version
        }

        return "\(version) (\(commitShortHash))"
    }

    private static func bundleString(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
