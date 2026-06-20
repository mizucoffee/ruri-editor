//
//  WorktreeInitializationStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class WorktreeInitializationStoreTests: XCTestCase {
    private let fileManager = FileManager.default

    func testMissingInitializationReturnsEmptyDocument() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let document = await WorktreeInitializationStore().load(
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        )

        XCTAssertEqual(document.initializationCommand, "")
    }

    func testSavesAndLoadsInitializationCommand() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let store = WorktreeInitializationStore()

        try await store.save(
            WorktreeInitializationDocument(initializationCommand: "npm install"),
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let document = await store.load(metadataDirectoryURL: metadataURL)

        XCTAssertEqual(document.initializationCommand, "npm install")
        XCTAssertTrue(fileManager.fileExists(atPath: metadataURL.appending(path: "worktree-initialization.json").path(percentEncoded: false)))
    }

    func testInvalidJSONFallsBackToEmptyDocument() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try "{ invalid".write(to: metadataURL.appending(path: "worktree-initialization.json"), atomically: true, encoding: .utf8)

        let document = await WorktreeInitializationStore().load(metadataDirectoryURL: metadataURL)

        XCTAssertEqual(document.initializationCommand, "")
    }

    func testSaveAddsRuriToLocalGitExcludeForRepoRootMetadata() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let excludeDirectoryURL = rootURL.appending(path: ".git/info", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: excludeDirectoryURL, withIntermediateDirectories: true)
        let excludeURL = excludeDirectoryURL.appending(path: "exclude")
        try "# local\n".write(to: excludeURL, atomically: true, encoding: .utf8)

        try await WorktreeInitializationStore().save(
            WorktreeInitializationDocument(initializationCommand: "npm install"),
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory),
            repositoryRootURL: rootURL
        )

        let excludeText = try String(contentsOf: excludeURL, encoding: .utf8)
        XCTAssertTrue(excludeText.split(whereSeparator: \.isNewline).contains(".ruri/"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
