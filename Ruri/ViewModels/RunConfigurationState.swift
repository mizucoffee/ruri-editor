//
//  RunConfigurationState.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class RunConfigurationState: ObservableObject {
    @Published private(set) var configurations: [RunConfiguration] = []
    @Published private(set) var activeConfigurationID: RunConfiguration.ID?
    @Published private(set) var currentError: EditorError?

    private let store: any RunConfigurationStoring
    private var metadataLocation: RunConfigurationMetadataLocation?
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(store: any RunConfigurationStoring = RunConfigurationStore()) {
        self.store = store
    }

    deinit {
        MainActor.assumeIsolated {
            loadTask?.cancel()
            saveTask?.cancel()
        }
    }

    var activeConfiguration: RunConfiguration? {
        guard let activeConfigurationID else { return configurations.first }
        return configurations.first { $0.id == activeConfigurationID } ?? configurations.first
    }

    var canRun: Bool {
        activeConfiguration != nil && metadataLocation != nil
    }

    var errorMessage: String? {
        currentError?.message
    }

    func updateMetadataLocation(_ location: RunConfigurationMetadataLocation?) {
        guard metadataLocation != location else { return }
        metadataLocation = location
        loadTask?.cancel()
        saveTask?.cancel()

        guard let location else {
            configurations = []
            activeConfigurationID = nil
            return
        }

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let document = await self.store.load(metadataDirectoryURL: location.metadataDirectoryURL)
            guard !Task.isCancelled, self.metadataLocation == location else { return }
            self.apply(document)
            self.loadTask = nil
        }
    }

    func selectConfiguration(_ id: RunConfiguration.ID) {
        guard configurations.contains(where: { $0.id == id }) else { return }
        activeConfigurationID = id
        scheduleSave()
    }

    func replaceConfigurations(
        _ updatedConfigurations: [RunConfiguration],
        activeConfigurationID requestedActiveConfigurationID: RunConfiguration.ID? = nil
    ) {
        configurations = updatedConfigurations
            .map { configuration in
                RunConfiguration(
                    id: configuration.id,
                    name: configuration.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    command: configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.name.isEmpty && !$0.command.isEmpty }

        if let requestedActiveConfigurationID,
           configurations.contains(where: { $0.id == requestedActiveConfigurationID }) {
            activeConfigurationID = requestedActiveConfigurationID
        } else if let activeConfigurationID,
                  configurations.contains(where: { $0.id == activeConfigurationID }) {
        } else {
            activeConfigurationID = configurations.first?.id
        }
        scheduleSave()
    }

    func clearError() {
        currentError = nil
    }

    private func apply(_ document: RunConfigurationDocument) {
        configurations = document.configurations
        activeConfigurationID = document.activeConfiguration?.id
    }

    private func scheduleSave() {
        guard let metadataLocation else { return }

        var document = RunConfigurationDocument(
            configurations: configurations,
            activeConfigurationID: activeConfigurationID
        )
        document.normalizeActiveConfiguration()
        activeConfigurationID = document.activeConfigurationID

        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await self?.store.save(
                    document,
                    metadataDirectoryURL: metadataLocation.metadataDirectoryURL,
                    repositoryRootURL: metadataLocation.repositoryRootURL
                )
            } catch {
                self?.currentError = EditorError(error)
            }
            self?.saveTask = nil
        }
    }
}
