//
//  CodePreviewController.swift
//  ruri
//

import Combine
import Foundation

@MainActor
final class CodePreviewController: ObservableObject {
    @Published private(set) var document: CodePreviewDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var failure: CodePreviewFailure?

    private struct CachedFile {
        let text: String
        let languageName: String?
        let syntaxRuns: [SyntaxHighlightRun]
    }

    private static let maximumCachedFileCount = 16

    private let fileService: ProjectFileService
    private let highlightingService: SyntaxHighlightingService
    private let maximumUTF16Length: Int
    private var currentRequest: CodePreviewRequest?
    private var loadTask: Task<Void, Never>?
    private var cachedFiles: [URL: CachedFile] = [:]
    private var cachedFileOrder: [URL] = []

    init(
        fileService: ProjectFileService = ProjectFileService(),
        highlightingService: SyntaxHighlightingService = SyntaxHighlightingService(),
        maximumUTF16Length: Int = 4_000_000
    ) {
        self.fileService = fileService
        self.highlightingService = highlightingService
        self.maximumUTF16Length = maximumUTF16Length
    }

    deinit {
        loadTask?.cancel()
    }

    func setRequest(_ request: CodePreviewRequest?) {
        guard request != currentRequest else { return }

        loadTask?.cancel()
        currentRequest = request

        guard let request else {
            document = nil
            isLoading = false
            failure = nil
            return
        }

        if let cachedFile = cachedFiles[request.url] {
            publish(cachedFile, for: request)
            return
        }

        isLoading = true
        failure = nil
        let debounces = document != nil
        loadTask = Task { [weak self] in
            await self?.load(request, debounces: debounces)
        }
    }

    func reset() {
        loadTask?.cancel()
        currentRequest = nil
        document = nil
        isLoading = false
        failure = nil
        cachedFiles.removeAll()
        cachedFileOrder.removeAll()
    }

    private func load(_ request: CodePreviewRequest, debounces: Bool) async {
        if debounces {
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                return
            }
        }

        let loadedFile: CachedFile
        do {
            let text = try await fileService.readUTF8File(at: request.url)
            guard text.utf16.count <= maximumUTF16Length else {
                fail(.fileTooLarge, for: request)
                return
            }

            let languageName = SyntaxLanguageResolver.languageName(for: request.url)
            let syntaxRuns = await highlightingService.highlightedRuns(for: text, languageName: languageName)
            loadedFile = CachedFile(text: text, languageName: languageName, syntaxRuns: syntaxRuns)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            fail(.unreadable, for: request)
            return
        }

        guard !Task.isCancelled else { return }
        store(loadedFile, for: request.url)
        publish(loadedFile, for: request)
    }

    private func publish(_ file: CachedFile, for request: CodePreviewRequest) {
        guard currentRequest == request else { return }

        document = CodePreviewDocument(
            request: request,
            text: file.text,
            languageName: file.languageName,
            syntaxRuns: file.syntaxRuns
        )
        isLoading = false
        failure = nil
    }

    private func fail(_ failure: CodePreviewFailure, for request: CodePreviewRequest) {
        guard currentRequest == request else { return }

        document = nil
        isLoading = false
        self.failure = failure
    }

    private func store(_ file: CachedFile, for url: URL) {
        if cachedFiles[url] == nil {
            cachedFileOrder.append(url)
        }
        cachedFiles[url] = file

        while cachedFileOrder.count > Self.maximumCachedFileCount {
            cachedFiles.removeValue(forKey: cachedFileOrder.removeFirst())
        }
    }
}
