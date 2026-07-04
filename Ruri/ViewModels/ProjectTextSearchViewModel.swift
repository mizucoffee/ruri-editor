//
//  ProjectTextSearchViewModel.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class ProjectTextSearchViewModel: ObservableObject {
    struct SelectionScrollRequest: Equatable {
        let resultID: ProjectTextSearchResult.ID
        let token: UUID
    }

    @Published private(set) var isPresented = false
    @Published var query = "" {
        didSet { scheduleSearch() }
    }
    @Published var directoryPath = "" {
        didSet { scheduleSearch() }
    }
    @Published var fileMask = "" {
        didSet { scheduleSearch() }
    }
    @Published var usesRegularExpression = false {
        didSet { scheduleSearch() }
    }
    @Published var isCaseSensitive = false {
        didSet { scheduleSearch() }
    }
    @Published private(set) var results: [ProjectTextSearchResult] = [] {
        didSet {
            syncPreview()
            snippetHighlighter.update(results: results)
        }
    }
    @Published private(set) var selectedResultID: ProjectTextSearchResult.ID? {
        didSet { syncPreview() }
    }
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var summary: ProjectTextSearchSummary?
    @Published private(set) var selectionScrollRequest: SelectionScrollRequest?
    @Published private(set) var snippetSyntaxRuns: [ProjectTextSearchResult.ID: [SyntaxHighlightRun]] = [:]

    let preview: CodePreviewController

    private let snippetHighlighter: ProjectTextSearchSnippetHighlighter
    private let searchService: ProjectTextSearchService
    private var activeProjectURL: URL?
    private var searchTask: Task<Void, Never>?

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedResult: ProjectTextSearchResult? {
        guard let selectedResultID else { return results.first }
        return results.first { $0.id == selectedResultID } ?? results.first
    }

    var summaryDescription: String? {
        guard let summary,
              hasQuery,
              !isSearching,
              errorMessage == nil else {
            return nil
        }

        let matchText = results.count == 1 ? "1 match" : "\(results.count) matches"
        let fileText = summary.matchedFileCount == 1 ? "1 file" : "\(summary.matchedFileCount) files"
        var parts = ["\(matchText) in \(fileText)"]

        if summary.didHitResultLimit {
            parts.append("limited")
        }

        if summary.skippedUnreadableFileCount > 0 {
            parts.append("\(summary.skippedUnreadableFileCount) skipped")
        }

        return parts.joined(separator: " · ")
    }

    init(
        searchService: ProjectTextSearchService = ProjectTextSearchService(),
        preview: CodePreviewController? = nil,
        snippetHighlighter: ProjectTextSearchSnippetHighlighter? = nil
    ) {
        self.searchService = searchService
        self.preview = preview ?? CodePreviewController()
        self.snippetHighlighter = snippetHighlighter ?? ProjectTextSearchSnippetHighlighter()

        self.snippetHighlighter.onRunsUpdate = { [weak self] runsByResultID in
            self?.snippetSyntaxRuns = runsByResultID
        }
    }

    deinit {
        searchTask?.cancel()
    }

    func present(projectURL: URL?) {
        guard let projectURL else { return }

        activeProjectURL = projectURL.standardizedFileURL
        isPresented = true
        errorMessage = nil
        results = []
        selectedResultID = nil
        selectionScrollRequest = nil
        summary = nil
        isSearching = false

        scheduleSearch(debounce: false)
    }

    func dismiss() {
        isPresented = false
        query = ""
        results = []
        selectedResultID = nil
        errorMessage = nil
        summary = nil
        isSearching = false
        searchTask?.cancel()
        preview.reset()
        snippetHighlighter.reset()
    }

    func updateActiveProject(_ projectURL: URL?) {
        guard isPresented else { return }

        guard let projectURL else {
            dismiss()
            return
        }

        let standardizedURL = projectURL.standardizedFileURL
        guard activeProjectURL != standardizedURL else { return }

        activeProjectURL = standardizedURL
        results = []
        selectedResultID = nil
        errorMessage = nil
        summary = nil
        preview.reset()
        snippetHighlighter.reset()
        scheduleSearch(debounce: false)
    }

    func invalidateResults(for projectURL: URL?) {
        guard let projectURL,
              isPresented,
              activeProjectURL == projectURL.standardizedFileURL else {
            return
        }

        results = []
        selectedResultID = nil
        summary = nil
        preview.reset()
        snippetHighlighter.reset()
        scheduleSearch(debounce: false)
    }

    func selectResult(_ id: ProjectTextSearchResult.ID) {
        guard results.contains(where: { $0.id == id }) else { return }
        selectedResultID = id
    }

    func selectNextResult() {
        moveSelection(offset: 1)
    }

    func selectPreviousResult() {
        moveSelection(offset: -1)
    }

    private func scheduleSearch() {
        scheduleSearch(debounce: true)
    }

    private func scheduleSearch(debounce: Bool) {
        searchTask?.cancel()

        guard isPresented else { return }
        guard let activeProjectURL else {
            resetSearchState()
            return
        }

        let options = currentOptions
        guard !options.trimmedQuery.isEmpty else {
            resetSearchState()
            return
        }

        isSearching = true
        errorMessage = nil
        summary = nil

        searchTask = Task { [weak self, searchService, activeProjectURL, options] in
            if debounce {
                do {
                    try await Task.sleep(nanoseconds: 220_000_000)
                } catch {
                    return
                }
            }

            do {
                let response = try await searchService.search(
                    projectURL: activeProjectURL,
                    options: options
                )
                guard !Task.isCancelled else { return }
                await self?.finishSearch(response, options: options, projectURL: activeProjectURL)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await self?.failSearch(error, options: options, projectURL: activeProjectURL)
            }
        }
    }

    private var currentOptions: ProjectTextSearchOptions {
        ProjectTextSearchOptions(
            query: query,
            directoryPath: directoryPath,
            fileMask: fileMask,
            usesRegularExpression: usesRegularExpression,
            isCaseSensitive: isCaseSensitive
        )
    }

    private func finishSearch(
        _ response: ProjectTextSearchResponse,
        options: ProjectTextSearchOptions,
        projectURL: URL
    ) {
        guard isPresented,
              activeProjectURL == projectURL,
              currentOptions == options else {
            return
        }

        isSearching = false
        errorMessage = nil
        results = response.results
        summary = response.summary
        repairSelection()
    }

    private func failSearch(
        _ error: Error,
        options: ProjectTextSearchOptions,
        projectURL: URL
    ) {
        guard isPresented,
              activeProjectURL == projectURL,
              currentOptions == options else {
            return
        }

        isSearching = false
        results = []
        selectedResultID = nil
        summary = nil
        errorMessage = error.localizedDescription
    }

    private func resetSearchState() {
        isSearching = false
        results = []
        selectedResultID = nil
        selectionScrollRequest = nil
        errorMessage = nil
        summary = nil
    }

    private func syncPreview() {
        preview.setRequest(selectedResult?.codePreviewRequest)
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
        requestSelectionScroll()
    }

    private func moveSelection(offset: Int) {
        guard !results.isEmpty else { return }

        let currentIndex = selectedResult.flatMap { selectedResult in
            results.firstIndex { $0.id == selectedResult.id }
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)

        selectedResultID = results[nextIndex].id
        requestSelectionScroll()
    }

    private func requestSelectionScroll() {
        guard let selectedResultID else { return }
        selectionScrollRequest = SelectionScrollRequest(resultID: selectedResultID, token: UUID())
    }
}
