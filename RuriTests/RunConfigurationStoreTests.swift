//
//  RunConfigurationStoreTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class RunConfigurationStoreTests: XCTestCase {
    private let fileManager = FileManager.default

    func testMissingConfigurationsReturnsEmptyDocument() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let document = await RunConfigurationStore().load(
            metadataDirectoryURL: rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        )

        XCTAssertEqual(document.configurations, [])
        XCTAssertNil(document.activeConfigurationID)
    }

    func testSavesAndLoadsConfigurations() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        let configuration = RunConfiguration(name: "Test", command: "swift test")
        let store = RunConfigurationStore()

        try await store.save(
            RunConfigurationDocument(
                configurations: [configuration],
                activeConfigurationID: configuration.id
            ),
            metadataDirectoryURL: metadataURL,
            repositoryRootURL: nil
        )

        let loaded = await store.load(metadataDirectoryURL: metadataURL)

        XCTAssertEqual(loaded.configurations, [configuration])
        XCTAssertEqual(loaded.activeConfigurationID, configuration.id)
        XCTAssertTrue(fileManager.fileExists(atPath: metadataURL.appending(path: "run-configurations.json").path(percentEncoded: false)))
    }

    func testActiveConfigurationFallsBackToFirstConfiguration() async throws {
        let configuration = RunConfiguration(name: "Test", command: "swift test")

        let document = RunConfigurationDocument(
            configurations: [configuration],
            activeConfigurationID: UUID()
        )

        XCTAssertEqual(document.activeConfigurationID, configuration.id)
    }

    func testInvalidJSONFallsBackToEmptyDocument() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let metadataURL = rootURL.appending(path: ".ruri", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try "{ invalid".write(to: metadataURL.appending(path: "run-configurations.json"), atomically: true, encoding: .utf8)

        let document = await RunConfigurationStore().load(metadataDirectoryURL: metadataURL)

        XCTAssertEqual(document.configurations, [])
        XCTAssertNil(document.activeConfigurationID)
    }

    func testSaveAddsRuriToLocalGitExcludeForRepoRootMetadata() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let excludeDirectoryURL = rootURL.appending(path: ".git/info", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: excludeDirectoryURL, withIntermediateDirectories: true)
        let excludeURL = excludeDirectoryURL.appending(path: "exclude")
        try "# local\n".write(to: excludeURL, atomically: true, encoding: .utf8)

        try await RunConfigurationStore().save(
            RunConfigurationDocument(),
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
