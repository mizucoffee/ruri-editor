//
//  ProjectFileSearchViewModelTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class ProjectFileSearchViewModelTests: XCTestCase {
    private let fileManager = FileManager.default

    func testUpdateActiveProjectBuildsIndexWithoutPresentingSearch() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL.appending(path: "Sources"), withIntermediateDirectories: false)
        try "app".write(to: rootURL.appending(path: "Sources/App.swift"), atomically: true, encoding: .utf8)

        let viewModel = ProjectFileSearchViewModel(fileService: try makeFileService())

        viewModel.updateActiveProject(rootURL)
        let fileCount = try await waitForIndexReady(in: viewModel)

        XCTAssertFalse(viewModel.isPresented)
        XCTAssertEqual(fileCount, 1)
    }

    func testQueryChangeResetsSelectionToFirstResult() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "ant".write(to: rootURL.appending(path: "Ant.swift"), atomically: true, encoding: .utf8)
        try "apple".write(to: rootURL.appending(path: "Apple.swift"), atomically: true, encoding: .utf8)
        try "banana".write(to: rootURL.appending(path: "Banana.swift"), atomically: true, encoding: .utf8)

        let viewModel = ProjectFileSearchViewModel(fileService: try makeFileService())

        viewModel.present(projectURL: rootURL)
        _ = try await waitForIndexReady(in: viewModel)

        viewModel.query = "a"
        try await waitForResultCount(3, in: viewModel)

        viewModel.selectNextResult()
        viewModel.selectNextResult()
        XCTAssertEqual(viewModel.selectedResultID, viewModel.results[2].id)

        // "an" ではBananaが2位に残るため、旧実装の「選択維持」だと先頭に戻らない
        viewModel.query = "an"
        try await waitForResultCount(2, in: viewModel)

        XCTAssertEqual(viewModel.selectedResultID, viewModel.results.first?.id)
    }

    private func waitForResultCount(
        _ count: Int,
        in viewModel: ProjectFileSearchViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await TestSupport.waitUntil("file search results count \(count)", file: file, line: line) {
            viewModel.results.count == count
        }
    }

    private func waitForIndexReady(
        in viewModel: ProjectFileSearchViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Int {
        var readyFileCount: Int?
        try await TestSupport.waitUntil("file search index readiness", file: file, line: line) {
            if case .ready(let fileCount) = viewModel.indexStatus {
                readyFileCount = fileCount
                return true
            }

            return false
        }
        return try XCTUnwrap(readyFileCount, file: file, line: line)
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }

    private func makeFileService() throws -> ProjectFileService {
        guard let executableURL = ripgrepExecutableURL() else {
            throw XCTSkip("ripgrep is not available in PATH.")
        }

        return ProjectFileService(searchExecutableURL: executableURL)
    }

    private func ripgrepExecutableURL() -> URL? {
        for directory in searchPathDirectories() {
            let url = URL(filePath: directory).appending(path: "rg")
            if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }

        return nil
    }

    private func searchPathDirectories() -> [String] {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]

        return path
            .split(separator: ":")
            .map(String.init) + defaults
    }
}
