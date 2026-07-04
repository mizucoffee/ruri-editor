//
//  ProjectFileSearchViewModel.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class ProjectFileSearchViewModel: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var query = "" {
        didSet {
            scheduleSearch()
        }
    }
    @Published private(set) var results: [ProjectFileSearchResult] = []
    @Published private(set) var selectedResultID: ProjectFileSearchResult.ID?
    @Published private(set) var isIndexing = false
    @Published private(set) var indexStatus = ProjectFileSearchIndexStatusState.inactive
    @Published private(set) var errorMessage: String?

    private let fileService: ProjectFileService
    private var activeProjectURL: URL?
    private var indexesByProjectURL: [URL: ProjectFileSearchIndex] = [:]
    private var indexingTasksByProjectURL: [URL: Task<Void, Never>] = [:]
    private var indexingErrorsByProjectURL: [URL: String] = [:]
    private var searchTask: Task<Void, Never>?

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedResult: ProjectFileSearchResult? {
        guard let selectedResultID else { return results.first }
        return results.first { $0.id == selectedResultID } ?? results.first
    }

    init(fileService: ProjectFileService = ProjectFileService()) {
        self.fileService = fileService
    }

    deinit {
        indexingTasksByProjectURL.values.forEach { $0.cancel() }
        searchTask?.cancel()
    }

    func present(projectURL: URL?) {
        guard let projectURL else { return }

        let standardizedURL = projectURL.standardizedFileURL
        activeProjectURL = standardizedURL
        isPresented = true
        errorMessage = nil
        query = ""
        results = []
        selectedResultID = nil
        refreshIndexStatus()

        ensureIndex(for: standardizedURL)
    }

    func dismiss() {
        isPresented = false
        query = ""
        results = []
        selectedResultID = nil
        errorMessage = nil
        searchTask?.cancel()
    }

    func updateActiveProject(_ projectURL: URL?) {
        guard let projectURL else {
            activeProjectURL = nil
            refreshIndexStatus()
            dismiss()
            return
        }

        let standardizedURL = projectURL.standardizedFileURL
        let didChangeProject = activeProjectURL != standardizedURL

        activeProjectURL = standardizedURL
        refreshIndexStatus()
        if !isPresented || !didChangeProject {
            ensureIndex(for: standardizedURL)
            return
        }

        query = ""
        results = []
        selectedResultID = nil
        errorMessage = nil
        ensureIndex(for: standardizedURL)
    }

    func invalidateIndex(for projectURL: URL?) {
        guard let projectURL else { return }

        let standardizedURL = projectURL.standardizedFileURL
        indexesByProjectURL[standardizedURL] = nil
        indexingErrorsByProjectURL[standardizedURL] = nil
        indexingTasksByProjectURL[standardizedURL]?.cancel()
        indexingTasksByProjectURL[standardizedURL] = nil

        guard activeProjectURL == standardizedURL else {
            return
        }

        refreshIndexStatus()
        guard isPresented else { return }

        results = []
        selectedResultID = nil
        ensureIndex(for: standardizedURL)
    }

    func selectResult(_ id: ProjectFileSearchResult.ID) {
        guard results.contains(where: { $0.id == id }) else { return }
        selectedResultID = id
    }

    func selectNextResult() {
        moveSelection(offset: 1)
    }

    func selectPreviousResult() {
        moveSelection(offset: -1)
    }

    private func ensureIndex(for projectURL: URL) {
        let standardizedURL = projectURL.standardizedFileURL

        if indexesByProjectURL[standardizedURL] != nil {
            isIndexing = false
            refreshIndexStatus()
            startSearch()
            return
        }

        if indexingTasksByProjectURL[standardizedURL] != nil {
            isIndexing = true
            refreshIndexStatus()
            return
        }

        isIndexing = true
        indexingErrorsByProjectURL[standardizedURL] = nil
        indexingTasksByProjectURL[standardizedURL] = Task { [weak self, fileService] in
            do {
                let entries = try await fileService.loadSearchEntries(at: standardizedURL)
                guard !Task.isCancelled else { return }
                self?.finishIndex(
                    ProjectFileSearchIndex(projectURL: standardizedURL, entries: entries),
                    for: standardizedURL
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.failIndexing(error, for: standardizedURL)
            }
        }
        refreshIndexStatus()
    }

    private func finishIndex(_ index: ProjectFileSearchIndex, for projectURL: URL) {
        indexesByProjectURL[projectURL] = index
        indexingTasksByProjectURL[projectURL] = nil
        indexingErrorsByProjectURL[projectURL] = nil

        guard activeProjectURL == projectURL else { return }

        isIndexing = false
        errorMessage = nil
        refreshIndexStatus()
        startSearch()
    }

    private func failIndexing(_ error: Error, for projectURL: URL) {
        indexingTasksByProjectURL[projectURL] = nil
        let message = error.localizedDescription
        indexingErrorsByProjectURL[projectURL] = message

        guard activeProjectURL == projectURL else { return }

        isIndexing = false
        results = []
        selectedResultID = nil
        errorMessage = message
        refreshIndexStatus()
    }

    private func refreshIndexStatus() {
        guard let activeProjectURL else {
            indexStatus = .inactive
            return
        }

        if indexingTasksByProjectURL[activeProjectURL] != nil {
            indexStatus = .indexing
            return
        }

        if let errorMessage = indexingErrorsByProjectURL[activeProjectURL] {
            indexStatus = .failed(message: errorMessage)
            return
        }

        if let index = indexesByProjectURL[activeProjectURL] {
            indexStatus = .ready(fileCount: index.entries.count)
            return
        }

        indexStatus = .inactive
    }

    private func scheduleSearch() {
        startSearch()
    }

    private func startSearch() {
        searchTask?.cancel()

        guard isPresented else { return }
        guard let activeProjectURL,
              let index = indexesByProjectURL[activeProjectURL] else {
            results = []
            selectedResultID = nil
            return
        }

        let query = query
        searchTask = Task.detached(priority: .userInitiated) { [weak self, activeProjectURL, index, query] in
            guard !Task.isCancelled else { return }
            let results = index.search(matching: query) {
                Task.isCancelled
            }
            guard !Task.isCancelled else { return }

            await self?.finishSearch(results, query: query, projectURL: activeProjectURL)
        }
    }

    private func finishSearch(
        _ results: [ProjectFileSearchResult],
        query: String,
        projectURL: URL
    ) {
        guard isPresented,
              activeProjectURL == projectURL,
              self.query == query else {
            return
        }

        self.results = results
        repairSelection()
    }

    private func repairSelection() {
        guard !results.isEmpty else {
            selectedResultID = nil
            return
        }

        if let selectedResultID,
           results.contains(where: { $0.id == selectedResultID }) {
            return
        }

        selectedResultID = results[0].id
    }

    private func moveSelection(offset: Int) {
        guard !results.isEmpty else { return }

        let currentIndex = selectedResult.flatMap { selectedResult in
            results.firstIndex { $0.id == selectedResult.id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)

        selectedResultID = results[nextIndex].id
    }
}
