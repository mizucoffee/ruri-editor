//
//  WorktreeMetadataStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class WorktreeMetadataStoreTests: XCTestCase {
    private let fileManager = FileManager.default

    func testMissingMetadataReturnsEmptyMemo() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let memo = await WorktreeMetadataStore().memo(
            forBranch: "feature/missing",
            metadataDirectoryURL: rootURL.appending(path: ".ruri")
        )

        XCTAssertEqual(memo, "")
    }

    func testSavesAndLoadsBranchMemo() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        try await store.saveMemo(
            "Review authentication",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let memo = await store.memo(
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL
        )

        XCTAssertEqual(memo, "Review authentication")
        XCTAssertTrue(fileManager.fileExists(atPath: metadataURL.appending(path: "worktree-metadata.json").path(percentEncoded: false)))
    }

    func testSavesAndLoadsReviewBase() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        try await store.saveReviewBase(
            .branch("origin/main"),
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let reviewBase = await store.reviewBase(
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL
        )

        XCTAssertEqual(reviewBase, .branch("origin/main"))
    }

    func testMemoAndReviewBasePreserveEachOther() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        try await store.saveMemo(
            "Review authentication",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )
        try await store.saveReviewBase(
            .uncommitted,
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )
        try await store.saveMemo(
            "Updated memo",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let memo = await store.memo(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)
        let reviewBase = await store.reviewBase(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)

        XCTAssertEqual(memo, "Updated memo")
        XCTAssertEqual(reviewBase, .uncommitted)
    }

    func testInvalidJSONFallsBackToEmptyDocument() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try "{ invalid".write(to: metadataURL.appending(path: "worktree-metadata.json"), atomically: true, encoding: .utf8)

        let store = WorktreeMetadataStore()
        let missingMemo = await store.memo(forBranch: "main", metadataDirectoryURL: metadataURL)
        try await store.saveMemo(
            "Recovered",
            forBranch: "main",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        XCTAssertEqual(missingMemo, "")
        let recoveredMemo = await store.memo(forBranch: "main", metadataDirectoryURL: metadataURL)
        XCTAssertEqual(recoveredMemo, "Recovered")
    }

    func testMissingMetadataReturnsEmptyViewedReviewFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let viewedFiles = await WorktreeMetadataStore().viewedReviewFiles(
            forBranch: "feature/missing",
            metadataDirectoryURL: rootURL.appending(path: ".ruri")
        )

        XCTAssertEqual(viewedFiles, [:])
    }

    func testSavesAndLoadsViewedReviewFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        try await store.saveViewedReviewFile(
            path: "Sources/App.swift",
            fingerprint: "abc123",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )
        try await store.saveViewedReviewFile(
            path: "Sources/Other.swift",
            fingerprint: "def456",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let viewedFiles = await store.viewedReviewFiles(
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL
        )

        XCTAssertEqual(viewedFiles, [
            "Sources/App.swift": "abc123",
            "Sources/Other.swift": "def456"
        ])
    }

    func testNilFingerprintRemovesViewedReviewFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        try await store.saveViewedReviewFile(
            path: "Sources/App.swift",
            fingerprint: "abc123",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )
        try await store.saveViewedReviewFile(
            path: "Sources/App.swift",
            fingerprint: nil,
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let viewedFiles = await store.viewedReviewFiles(
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL
        )

        XCTAssertEqual(viewedFiles, [:])
    }

    func testViewedReviewFilesAreScopedPerBranchAndPreserveOtherMetadata() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        try await store.saveMemo(
            "Review authentication",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )
        try await store.saveReviewBase(
            .branch("main"),
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )
        try await store.saveViewedReviewFile(
            path: "Sources/App.swift",
            fingerprint: "abc123",
            forBranch: "feature/auth",
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let viewedFiles = await store.viewedReviewFiles(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)
        let otherBranchViewedFiles = await store.viewedReviewFiles(forBranch: "main", metadataDirectoryURL: metadataURL)
        let memo = await store.memo(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)
        let reviewBase = await store.reviewBase(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)

        XCTAssertEqual(viewedFiles, ["Sources/App.swift": "abc123"])
        XCTAssertEqual(otherBranchViewedFiles, [:])
        XCTAssertEqual(memo, "Review authentication")
        XCTAssertEqual(reviewBase, .branch("main"))
    }

    func testDocumentWithoutViewedReviewFilesStillDecodes() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try """
        {"version":1,"branches":{"feature/auth":{"memo":"Legacy"}}}
        """.write(to: metadataURL.appending(path: "worktree-metadata.json"), atomically: true, encoding: .utf8)

        let store = WorktreeMetadataStore()
        let viewedFiles = await store.viewedReviewFiles(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)
        let memo = await store.memo(forBranch: "feature/auth", metadataDirectoryURL: metadataURL)

        XCTAssertEqual(viewedFiles, [:])
        XCTAssertEqual(memo, "Legacy")
    }

    func testConcurrentSavesAcrossKindsDoNotLoseUpdates() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeMetadataStore()

        for index in 0..<10 {
            async let memoSave: Void = store.saveMemo(
                "memo-\(index)",
                forBranch: "main",
                metadataDirectoryURL: metadataURL,
                repositoryRootURL: nil
            )
            async let viewedSave: Void = store.saveViewedReviewFile(
                path: "File-\(index).txt",
                fingerprint: "fp-\(index)",
                forBranch: "main",
                metadataDirectoryURL: metadataURL,
                repositoryRootURL: nil
            )
            async let baseSave: Void = store.saveReviewBase(
                .branch("base-\(index)"),
                forBranch: "main",
                metadataDirectoryURL: metadataURL,
                repositoryRootURL: nil
            )
            _ = try await (memoSave, viewedSave, baseSave)
        }

        let viewedFiles = await store.viewedReviewFiles(forBranch: "main", metadataDirectoryURL: metadataURL)
        let memo = await store.memo(forBranch: "main", metadataDirectoryURL: metadataURL)
        let reviewBase = await store.reviewBase(forBranch: "main", metadataDirectoryURL: metadataURL)

        XCTAssertEqual(viewedFiles.count, 10)
        XCTAssertEqual(memo, "memo-9")
        XCTAssertEqual(reviewBase, .branch("base-9"))
    }

    func testSaveAddsRuriToLocalGitExcludeForRepoRootMetadata() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let excludeDirectoryURL = rootURL.appending(path: ".git/info", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: excludeDirectoryURL, withIntermediateDirectories: true)
        let excludeURL = excludeDirectoryURL.appending(path: "exclude")
        try "# local\n".write(to: excludeURL, atomically: true, encoding: .utf8)

        try await WorktreeMetadataStore().saveMemo(
            "Local",
            forBranch: "main",
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory),
            repositoryRootURL: rootURL
        )

        let excludeText = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(excludeText.split(whereSeparator: \.isNewline).contains(".ruri/"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }
}
