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
        for _ in 0..<100 {
            if case .ready(let fileCount) = viewModel.indexStatus {
                return fileCount
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for file search index readiness.", file: file, line: line)
        return -1
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
