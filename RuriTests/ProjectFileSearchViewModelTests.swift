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
