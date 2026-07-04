//
//  EditorCodeNavigationStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorCodeNavigationStoreTests: XCTestCase {
    private let store = EditorCodeNavigationStore()
    private let workspaceURL = URL(filePath: "/tmp/Project")

    private func target(
        path: String,
        location: Int = 0,
        length: Int = 1,
        kind: SymbolNavigationTarget.Kind = .method
    ) -> SymbolNavigationTarget {
        SymbolNavigationTarget(
            url: URL(filePath: path),
            range: TextRange(location: location, length: length),
            name: "symbol",
            kind: kind
        )
    }

    func testResolutionActionNavigatesToImplementation() {
        let implementationTarget = target(path: "/tmp/Project/Main.java")

        let action = store.resolutionAction(for: .implementation(implementationTarget))

        XCTAssertEqual(action, .navigate(implementationTarget))
    }

    func testResolutionActionSkipsEmptyReferences() {
        let action = store.resolutionAction(for: .references([]))

        XCTAssertEqual(action, .skip)
    }

    func testResolutionActionNavigatesToSingleReference() {
        let referenceTarget = target(path: "/tmp/Project/Main.java", kind: .usage)

        let action = store.resolutionAction(for: .references([referenceTarget]))

        XCTAssertEqual(action, .navigate(referenceTarget))
    }

    func testResolutionActionCollectsMultipleReferences() {
        let first = target(path: "/tmp/Project/Main.java", location: 0, kind: .usage)
        let second = target(path: "/tmp/Project/Other.java", location: 5, kind: .usage)

        let action = store.resolutionAction(for: .references([first, second]))

        XCTAssertEqual(action, .collectReferences([first, second]))
    }

    func testReviewDiffSourceActionRejectsFileOutsideWorkspace() {
        let action = store.reviewDiffSourceAction(
            fileURL: URL(filePath: "/tmp/Elsewhere/Main.java"),
            side: .new,
            workspaceURL: workspaceURL,
            documents: [],
            reviewDiffState: .unavailable
        )

        XCTAssertEqual(action, .reject)
    }

    func testReviewDiffSourceActionPrefersOpenDocumentOnNewSide() {
        let fileURL = URL(filePath: "/tmp/Project/Main.java")
        let document = OpenDocument(
            url: fileURL,
            text: "edited contents",
            lastSavedText: "saved contents"
        )

        let action = store.reviewDiffSourceAction(
            fileURL: fileURL,
            side: .new,
            workspaceURL: workspaceURL,
            documents: [document],
            reviewDiffState: .unavailable
        )

        XCTAssertEqual(
            action,
            .useOpenDocument(
                text: "edited contents",
                documentID: fileURL,
                fileURL: fileURL.standardizedFileURL
            )
        )
    }

    func testReviewDiffSourceActionReadsFileOnNewSideWithoutOpenDocument() {
        let fileURL = URL(filePath: "/tmp/Project/sub/../Main.java")

        let action = store.reviewDiffSourceAction(
            fileURL: fileURL,
            side: .new,
            workspaceURL: workspaceURL,
            documents: [],
            reviewDiffState: .unavailable
        )

        XCTAssertEqual(action, .readFile(URL(filePath: "/tmp/Project/Main.java")))
    }

    func testReviewDiffSourceActionRejectsOldSideWithoutLoadedSnapshot() {
        let action = store.reviewDiffSourceAction(
            fileURL: URL(filePath: "/tmp/Project/Main.java"),
            side: .old,
            workspaceURL: workspaceURL,
            documents: [],
            reviewDiffState: .loading
        )

        XCTAssertEqual(action, .reject)
    }

    func testReviewDiffSourceActionReadsBaseFileOnOldSide() {
        let snapshot = GitReviewDiffSnapshot(
            baseBranch: "main",
            targetBranch: .branch("feature"),
            targetWorktreeRootURL: workspaceURL,
            mergeBaseRevision: "abc123",
            files: []
        )

        let action = store.reviewDiffSourceAction(
            fileURL: URL(filePath: "/tmp/Project/src/Main.java"),
            side: .old,
            workspaceURL: workspaceURL,
            documents: [],
            reviewDiffState: .loaded(snapshot)
        )

        XCTAssertEqual(
            action,
            .readBaseFile(
                revision: "abc123",
                relativePath: "src/Main.java",
                rootURL: workspaceURL.standardizedFileURL,
                fileURL: URL(filePath: "/tmp/Project/src/Main.java")
            )
        )
    }

    func testUsageResultsDeduplicatesByLocation() {
        let text = "alpha\nbeta\n"
        let first = target(path: "/tmp/Project/Main.java", location: 0, length: 5, kind: .usage)
        let duplicate = target(path: "/tmp/Project/Main.java", location: 0, length: 5, kind: .usage)
        let second = target(path: "/tmp/Project/Main.java", location: 6, length: 4, kind: .usage)

        let results = store.usageResults(
            for: [(target: first, text: text), (target: duplicate, text: text), (target: second, text: text)],
            projectURL: workspaceURL
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.lineNumber), [1, 2])
        XCTAssertEqual(results.map(\.lineText), ["alpha", "beta"])
    }

    func testUsageResultsSortsProductionFilesBeforeTestDirectories() {
        let testTarget = target(path: "/tmp/Project/test/MainTest.java", kind: .usage)
        let productionTarget = target(path: "/tmp/Project/zzz/Main.java", kind: .usage)

        let results = store.usageResults(
            for: [(target: testTarget, text: "body"), (target: productionTarget, text: "body")],
            projectURL: workspaceURL
        )

        XCTAssertEqual(results.map(\.relativePath), ["zzz/Main.java", "test/MainTest.java"])
    }

    func testResultsTitleUsesUsagesForUsageOnlyTargets() {
        let targets = [
            target(path: "/tmp/Project/Main.java", kind: .usage),
            target(path: "/tmp/Project/Other.java", kind: .usage)
        ]

        XCTAssertEqual(store.resultsTitle(for: targets), "Usages")
    }

    func testResultsTitleUsesLocationsForMixedTargets() {
        let targets = [
            target(path: "/tmp/Project/Main.java", kind: .usage),
            target(path: "/tmp/Project/Other.java", kind: .method)
        ]

        XCTAssertEqual(store.resultsTitle(for: targets), "Locations")
    }

    func testOpenDocumentsIncludesOnlyJavaDocuments() {
        let javaDocument = OpenDocument(
            url: URL(filePath: "/tmp/Project/Main.java"),
            text: "java text",
            lastSavedText: "java text"
        )
        let markdownDocument = OpenDocument(
            url: URL(filePath: "/tmp/Project/README.md"),
            text: "markdown text",
            lastSavedText: "markdown text"
        )

        let documents = store.openDocuments(from: [javaDocument, markdownDocument])

        XCTAssertEqual(
            documents,
            [SymbolNavigationOpenDocument(url: javaDocument.url, text: "java text")]
        )
    }

    func testOpenDocumentsIncludingNonJavaSourceReturnsBaseDocuments() {
        let javaDocument = OpenDocument(
            url: URL(filePath: "/tmp/Project/Main.java"),
            text: "java text",
            lastSavedText: "java text"
        )
        let source = SymbolNavigationOpenDocument(
            url: URL(filePath: "/tmp/Project/README.md"),
            text: "markdown text"
        )

        let documents = store.openDocuments(from: [javaDocument], including: source)

        XCTAssertEqual(
            documents,
            [SymbolNavigationOpenDocument(url: javaDocument.url, text: "java text")]
        )
    }

    func testOpenDocumentsIncludingReplacesMatchingJavaDocument() {
        let fileURL = URL(filePath: "/tmp/Project/Main.java")
        let javaDocument = OpenDocument(
            url: fileURL,
            text: "stale text",
            lastSavedText: "stale text"
        )
        let source = SymbolNavigationOpenDocument(url: fileURL, text: "fresh text")

        let documents = store.openDocuments(from: [javaDocument], including: source)

        XCTAssertEqual(documents, [source])
    }

    func testOpenDocumentsIncludingAppendsNewJavaDocument() {
        let javaDocument = OpenDocument(
            url: URL(filePath: "/tmp/Project/Main.java"),
            text: "java text",
            lastSavedText: "java text"
        )
        let source = SymbolNavigationOpenDocument(
            url: URL(filePath: "/tmp/Project/Other.java"),
            text: "other text"
        )

        let documents = store.openDocuments(from: [javaDocument], including: source)

        XCTAssertEqual(
            documents,
            [SymbolNavigationOpenDocument(url: javaDocument.url, text: "java text"), source]
        )
    }

    func testLineLocalRangeConvertsToLineRelativeOffsets() {
        let text = "alpha\nbeta gamma\n"

        let range = store.lineLocalRange(
            for: NSRange(location: 11, length: 5),
            lineNumber: 2,
            in: text
        )

        XCTAssertEqual(range, NSRange(location: 5, length: 5))
    }

    func testLineLocalRangeReturnsNilWhenRangeMissesLine() {
        let text = "alpha\nbeta\n"

        let range = store.lineLocalRange(
            for: NSRange(location: 0, length: 5),
            lineNumber: 2,
            in: text
        )

        XCTAssertNil(range)
    }

    func testLineLocalRangeClipsPartialOverlapToLine() {
        let text = "alpha\nbeta\n"

        let range = store.lineLocalRange(
            for: NSRange(location: 3, length: 5),
            lineNumber: 2,
            in: text
        )

        XCTAssertEqual(range, NSRange(location: 0, length: 2))
    }

    func testClampedRangeMovesNotFoundLocationToEnd() {
        let range = store.clampedRange(
            NSRange(location: NSNotFound, length: 3),
            toUTF16Length: 10
        )

        XCTAssertEqual(range, NSRange(location: 10, length: 0))
    }

    func testClampedRangeClampsNegativeLocationToZero() {
        let range = store.clampedRange(
            NSRange(location: -4, length: 3),
            toUTF16Length: 10
        )

        XCTAssertEqual(range, NSRange(location: 0, length: 3))
    }

    func testClampedRangeTrimsLengthToRemainingText() {
        let range = store.clampedRange(
            NSRange(location: 8, length: 5),
            toUTF16Length: 10
        )

        XCTAssertEqual(range, NSRange(location: 8, length: 2))
    }

    func testClampedRangeCollapsesToZeroInEmptyText() {
        let range = store.clampedRange(
            NSRange(location: 4, length: 5),
            toUTF16Length: 0
        )

        XCTAssertEqual(range, NSRange(location: 0, length: 0))
    }
}
