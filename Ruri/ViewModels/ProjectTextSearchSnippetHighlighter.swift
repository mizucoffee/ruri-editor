//
//  ProjectTextSearchSnippetHighlighter.swift
//  ruri
//

import Foundation

@MainActor
final class ProjectTextSearchSnippetHighlighter {
    var onRunsUpdate: (([ProjectTextSearchResult.ID: [SyntaxHighlightRun]]) -> Void)?

    private static let maximumCachedFileCount = 32

    private let fileService: ProjectFileService
    private let highlightingService: SyntaxHighlightingService
    private var cachedFileRuns: [URL: [SyntaxHighlightRun]] = [:]
    private var cachedFileOrder: [URL] = []
    private var highlightTask: Task<Void, Never>?

    init(
        fileService: ProjectFileService = ProjectFileService(),
        highlightingService: SyntaxHighlightingService = SyntaxHighlightingService()
    ) {
        self.fileService = fileService
        self.highlightingService = highlightingService
    }

    deinit {
        highlightTask?.cancel()
    }

    func update(results: [ProjectTextSearchResult]) {
        highlightTask?.cancel()

        guard !results.isEmpty else {
            onRunsUpdate?([:])
            return
        }

        highlightTask = Task { [weak self] in
            await self?.highlight(results)
        }
    }

    func reset() {
        highlightTask?.cancel()
        cachedFileRuns.removeAll()
        cachedFileOrder.removeAll()
        onRunsUpdate?([:])
    }

    private func highlight(_ results: [ProjectTextSearchResult]) async {
        let resultsByURL = Dictionary(grouping: results, by: \.url)
        let cachedURLs = resultsByURL.keys.filter { cachedFileRuns[$0] != nil }
        let uncachedURLs = resultsByURL.keys.filter { cachedFileRuns[$0] == nil }

        var runsByResultID: [ProjectTextSearchResult.ID: [SyntaxHighlightRun]] = [:]
        for url in cachedURLs + uncachedURLs {
            guard !Task.isCancelled else { return }

            let fileRuns: [SyntaxHighlightRun]
            if let cachedRuns = cachedFileRuns[url] {
                fileRuns = cachedRuns
            } else {
                fileRuns = await loadFileRuns(for: url)
                guard !Task.isCancelled else { return }
                store(fileRuns, for: url)
            }

            guard !fileRuns.isEmpty, let fileResults = resultsByURL[url] else { continue }

            for result in fileResults {
                runsByResultID[result.id] = Self.lineLocalRuns(from: fileRuns, for: result)
            }
            onRunsUpdate?(runsByResultID)
        }
    }

    private func loadFileRuns(for url: URL) async -> [SyntaxHighlightRun] {
        guard let languageName = SyntaxLanguageResolver.languageName(for: url),
              let text = try? await fileService.readUTF8File(at: url) else {
            return []
        }

        return await highlightingService.highlightedRuns(for: text, languageName: languageName)
    }

    private func store(_ runs: [SyntaxHighlightRun], for url: URL) {
        if cachedFileRuns[url] == nil {
            cachedFileOrder.append(url)
        }
        cachedFileRuns[url] = runs

        while cachedFileOrder.count > Self.maximumCachedFileCount {
            cachedFileRuns.removeValue(forKey: cachedFileOrder.removeFirst())
        }
    }

    nonisolated static func lineLocalRuns(
        from fileRuns: [SyntaxHighlightRun],
        for result: ProjectTextSearchResult
    ) -> [SyntaxHighlightRun] {
        let lineStart = result.matchRange.location - result.lineMatchRange.location
        let lineLength = (result.lineText as NSString).length
        let lineEnd = lineStart + lineLength
        guard lineStart >= 0, lineLength > 0 else { return [] }

        var localRuns: [SyntaxHighlightRun] = []
        for run in fileRuns {
            let start = max(run.location, lineStart)
            let end = min(run.location + run.length, lineEnd)
            guard start < end else { continue }

            localRuns.append(
                SyntaxHighlightRun(location: start - lineStart, length: end - start, role: run.role)
            )
        }
        return localRuns
    }
}
