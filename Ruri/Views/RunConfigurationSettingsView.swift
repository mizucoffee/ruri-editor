//
//  RunConfigurationSettingsView.swift
//  ruri
//

import SwiftUI

struct RunConfigurationSettingsView: View {
    @State private var draftConfigurations: [RunConfiguration]
    @State private var selectedConfigurationID: RunConfiguration.ID?

    let save: ([RunConfiguration], RunConfiguration.ID?) -> Void
    let cancel: () -> Void

    init(
        configurations: [RunConfiguration],
        activeConfigurationID: RunConfiguration.ID?,
        save: @escaping ([RunConfiguration], RunConfiguration.ID?) -> Void,
        cancel: @escaping () -> Void
    ) {
        _draftConfigurations = State(initialValue: configurations)
        _selectedConfigurationID = State(initialValue: activeConfigurationID ?? configurations.first?.id)
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppText.runConfigurationsTitle)
                    .font(.headline)
                Spacer()
                Button {
                    addConfiguration()
                } label: {
                    Label(AppText.addRunConfigurationButton, systemImage: "plus")
                }
            }

            if draftConfigurations.isEmpty {
                ContentUnavailableView(
                    "No Run Configurations",
                    systemImage: "play.slash",
                    description: Text("Add a shell command to enable Run.")
                )
                .frame(minHeight: 180)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($draftConfigurations) { $configuration in
                            runConfigurationRow($configuration)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button(AppText.cancelButton) {
                    cancel()
                }
                Button(AppText.doneButton) {
                    save(validConfigurations, normalizedSelectedConfigurationID)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .frame(minHeight: 360)
    }

    private var validConfigurations: [RunConfiguration] {
        draftConfigurations
            .map { configuration in
                RunConfiguration(
                    id: configuration.id,
                    name: configuration.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    command: configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.name.isEmpty && !$0.command.isEmpty }
    }

    private var normalizedSelectedConfigurationID: RunConfiguration.ID? {
        if let selectedConfigurationID,
           validConfigurations.contains(where: { $0.id == selectedConfigurationID }) {
            return selectedConfigurationID
        }

        return validConfigurations.first?.id
    }

    private func runConfigurationRow(_ configuration: Binding<RunConfiguration>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                selectedConfigurationID = configuration.wrappedValue.id
            } label: {
                Image(systemName: selectedConfigurationID == configuration.wrappedValue.id ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.plain)
            .help("Set Active Run Configuration")

            VStack(spacing: 8) {
                TextField(AppText.runConfigurationNamePlaceholder, text: configuration.name)
                TextField(AppText.runConfigurationCommandPlaceholder, text: configuration.command)
                    .font(.system(.body, design: .monospaced))
            }

            Button {
                deleteConfiguration(configuration.wrappedValue.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Run Configuration")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addConfiguration() {
        let configuration = RunConfiguration(name: "Run", command: "")
        draftConfigurations.append(configuration)
        selectedConfigurationID = configuration.id
    }

    private func deleteConfiguration(_ id: RunConfiguration.ID) {
        draftConfigurations.removeAll { $0.id == id }
        if selectedConfigurationID == id {
            selectedConfigurationID = draftConfigurations.first?.id
        }
    }
}
