//
//  EditorCodeNavigationStore.swift
//  ruri
//

import Foundation

struct EditorCodeNavigationStore {
    enum ResolutionAction: Equatable {
        case skip
        case navigate(SymbolNavigationTarget)
        case collectReferences([SymbolNavigationTarget])
    }

    enum ReviewDiffSourceAction: Equatable {
        case reject
        case useOpenDocument(text: String, documentID: OpenDocument.ID, fileURL: URL)
        case readFile(URL)
        case readBaseFile(revision: String, relativePath: String, rootURL: URL, fileURL: URL)
    }

    func resolutionAction(for resolution: SymbolNavigationResolution) -> ResolutionAction {
        switch resolution {
        case .implementation(let target):
            return .navigate(target)

        case .references(let targets):
            guard !targets.isEmpty else { return .skip }
            if targets.count == 1,
               let target = targets.first {
                return .navigate(target)
            }

            return .collectReferences(targets)
        }
    }

    func reviewDiffSourceAction(
        fileURL: URL,
        side: ReviewDiffCodeNavigationSide,
        workspaceURL: URL,
        documents: [OpenDocument],
        reviewDiffState: ReviewDiffState
    ) -> ReviewDiffSourceAction {
        let fileURL = fileURL.standardizedFileURL
        guard FileURLRewriter.isDescendantOrSame(fileURL, of: workspaceURL) else {
            return .reject
        }

        switch side {
        case .new:
            let openDocument = documents.first { document in
                FileURLRewriter.urlsMatch(document.url, fileURL)
            }

            if let openDocument {
                return .useOpenDocument(
                    text: openDocument.text,
                    documentID: openDocument.id,
                    fileURL: fileURL
                )
            }

            return .readFile(fileURL)

        case .old:
            guard case .loaded(let snapshot) = reviewDiffState,
                  let relativePath = FileURLRewriter.relativePath(
                    from: snapshot.targetWorktreeRootURL,
                    to: fileURL
                  ) else {
                return .reject
            }

            return .readBaseFile(
                revision: snapshot.baseRevision,
                relativePath: relativePath,
                rootURL: snapshot.targetWorktreeRootURL,
                fileURL: fileURL
            )
        }
    }

    func usageResults(
        for targets: [(target: SymbolNavigationTarget, text: String)],
        projectURL: URL
    ) -> [CodeUsageResult] {
        var seen = Set<CodeUsageResult.ID>()
        var results: [CodeUsageResult] = []

        for (target, text) in targets {
            let result = CodeUsageResult.result(for: target, text: text, projectURL: projectURL)
            guard seen.insert(result.id).inserted else { continue }
            results.append(result)
        }

        return CodeUsageResult.sorted(results)
    }

    func resultsTitle(for targets: [SymbolNavigationTarget]) -> String {
        targets.allSatisfy { $0.kind == .usage } ? "Usages" : "Locations"
    }

    func openDocuments(from documents: [OpenDocument]) -> [SymbolNavigationOpenDocument] {
        documents.compactMap { document in
            guard document.url.pathExtension.lowercased() == "java" else {
                return nil
            }

            return SymbolNavigationOpenDocument(url: document.url, text: document.text)
        }
    }

    func openDocuments(
        from documents: [OpenDocument],
        including sourceDocument: SymbolNavigationOpenDocument
    ) -> [SymbolNavigationOpenDocument] {
        guard sourceDocument.url.pathExtension.lowercased() == "java" else {
            return openDocuments(from: documents)
        }

        var openDocuments = openDocuments(from: documents)
        if let existingIndex = openDocuments.firstIndex(where: { document in
            FileURLRewriter.urlsMatch(document.url, sourceDocument.url)
        }) {
            openDocuments[existingIndex] = sourceDocument
        } else {
            openDocuments.append(sourceDocument)
        }
        return openDocuments
    }

    func lineLocalRange(
        for range: NSRange,
        lineNumber: Int,
        in text: String
    ) -> NSRange? {
        guard let lineRange = ReviewDiffCodeNavigationRequest.lineContentRange(
            lineNumber: lineNumber,
            in: text
        ) else {
            return nil
        }

        let lowerBound = max(range.location, lineRange.location)
        let upperBound = min(NSMaxRange(range), NSMaxRange(lineRange))
        guard lowerBound < upperBound else { return nil }
        return NSRange(location: lowerBound - lineRange.location, length: upperBound - lowerBound)
    }

    func clampedRange(_ range: NSRange, toUTF16Length length: Int) -> NSRange {
        range.clamped(toUTF16Length: length)
    }
}
