//
//  WorktreeInitializationState.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class WorktreeInitializationState: ObservableObject {
    @Published private(set) var command = ""
    @Published private(set) var currentError: EditorError?

    private let store: any WorktreeInitializationStoring
    private var metadataLocation: WorktreeInitializationMetadataLocation?
    private var loadTask: Task<Void, Never>?

    init(store: any WorktreeInitializationStoring = WorktreeInitializationStore()) {
        self.store = store
    }

    deinit {
        MainActor.assumeIsolated {
            loadTask?.cancel()
        }
    }

    var errorMessage: String? {
        currentError?.message
    }

    func updateMetadataLocation(_ location: WorktreeInitializationMetadataLocation?) {
        guard metadataLocation != location else { return }
        metadataLocation = location
        loadTask?.cancel()

        guard let location else {
            command = ""
            return
        }

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let document = await self.store.load(metadataDirectoryURL: location.metadataDirectoryURL)
            guard !Task.isCancelled, self.metadataLocation == location else { return }
            self.command = document.initializationCommand
            self.loadTask = nil
        }
    }

    func saveCommand(_ command: String) async throws {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        self.command = trimmedCommand
        currentError = nil

        guard let metadataLocation else { return }

        do {
            try await store.save(
                WorktreeInitializationDocument(initializationCommand: trimmedCommand),
                metadataDirectoryURL: metadataLocation.metadataDirectoryURL,
                repositoryRootURL: metadataLocation.repositoryRootURL
            )
        } catch {
            currentError = EditorError(error)
            throw error
        }
    }

    func clearError() {
        currentError = nil
    }
}
