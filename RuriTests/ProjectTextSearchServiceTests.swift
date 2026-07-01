//
//  ProjectTextSearchServiceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class ProjectTextSearchServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSearchScansNonIgnoredUTF8FilesAndSkipsMetadataDirectories() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        *.log
        Ignored/
        """.write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: rootURL.appending(path: ".git"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: ".ruri"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: "Ignored"), withIntermediateDirectories: false)
        try "Needle in app".write(to: rootURL.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "needle in hidden".write(to: rootURL.appending(path: ".env"), atomically: true, encoding: .utf8)
        try "needle in log".write(to: rootURL.appending(path: "debug.log"), atomically: true, encoding: .utf8)
        try "needle in ignored".write(to: rootURL.appending(path: "Ignored/Generated.swift"), atomically: true, encoding: .utf8)
        try "needle in git".write(to: rootURL.appending(path: ".git/HEAD"), atomically: true, encoding: .utf8)
        try "needle in ruri".write(to: rootURL.appending(path: ".ruri/worktree-metadata.json"), atomically: true, encoding: .utf8)

        let response = try await makeSearchService().search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(query: "needle")
        )

        XCTAssertEqual(response.results.map(\.relativePath).sorted(), [".env", "App.swift"])
        XCTAssertEqual(response.summary.matchedFileCount, 2)
    }

    func testSearchRespectsGitIgnoreOutsideGitRepository() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "*.log\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "needle".write(to: rootURL.appending(path: "debug.log"), atomically: true, encoding: .utf8)
        try "needle".write(to: rootURL.appending(path: "Notes.txt"), atomically: true, encoding: .utf8)

        let response = try await makeSearchService().search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(query: "needle")
        )

        XCTAssertEqual(response.results.map(\.relativePath), ["Notes.txt"])
    }

    func testSearchAppliesDirectoryAndGlobFileMask() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL.appending(path: "Sources"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: "Tests"), withIntermediateDirectories: false)
        try "target".write(to: rootURL.appending(path: "Sources/App.swift"), atomically: true, encoding: .utf8)
        try "target".write(to: rootURL.appending(path: "Sources/AppTests.swift"), atomically: true, encoding: .utf8)
        try "target".write(to: rootURL.appending(path: "Tests/AppTests.swift"), atomically: true, encoding: .utf8)

        let response = try await makeSearchService().search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(
                query: "target",
                directoryPath: "Sources",
                fileMask: "*.swift,!*Tests.swift"
            )
        )

        XCTAssertEqual(response.results.map(\.relativePath), ["Sources/App.swift"])
    }

    func testSearchPrioritizesNonTestFilesOverTestFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(
            at: rootURL.appending(path: "Sources"),
            withIntermediateDirectories: false
        )
        try fileManager.createDirectory(
            at: rootURL.appending(path: "Tests"),
            withIntermediateDirectories: false
        )
        try fileManager.createDirectory(
            at: rootURL.appending(path: "Tests/Helpers"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: rootURL.appending(path: "Docs"),
            withIntermediateDirectories: false
        )
        try "needle".write(to: rootURL.appending(path: "Docs/App.swift"), atomically: true, encoding: .utf8)
        try "needle".write(to: rootURL.appending(path: "Sources/App.swift"), atomically: true, encoding: .utf8)
        try "needle".write(to: rootURL.appending(path: "Tests/App.swift"), atomically: true, encoding: .utf8)
        try "needle".write(to: rootURL.appending(path: "Tests/Helpers/Helper.swift"), atomically: true, encoding: .utf8)

        let response = try await makeSearchService().search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(query: "needle")
        )

        XCTAssertEqual(
            response.results.map(\.relativePath),
            [
                "Docs/App.swift",
                "Sources/App.swift",
                "Tests/App.swift",
                "Tests/Helpers/Helper.swift"
            ]
        )
    }

    func testSearchSupportsRegexAndCaseSensitivity() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        final TODO-123
        final todo-456
        """.write(to: rootURL.appending(path: "Notes.txt"), atomically: true, encoding: .utf8)

        let searchService = try makeSearchService()
        let caseSensitiveResponse = try await searchService.search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(
                query: "TODO-\\d+",
                usesRegularExpression: true,
                isCaseSensitive: true
            )
        )
        let caseInsensitiveResponse = try await searchService.search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(
                query: "TODO-\\d+",
                usesRegularExpression: true,
                isCaseSensitive: false
            )
        )

        XCTAssertEqual(caseSensitiveResponse.results.count, 1)
        XCTAssertEqual(caseSensitiveResponse.results.first?.lineNumber, 1)
        XCTAssertEqual(caseSensitiveResponse.results.first?.column, 7)
        XCTAssertEqual(caseInsensitiveResponse.results.count, 2)
    }

    func testSearchReportsInvalidRegex() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "text".write(to: rootURL.appending(path: "Note.txt"), atomically: true, encoding: .utf8)

        do {
            _ = try await makeSearchService().search(
                projectURL: rootURL,
                options: ProjectTextSearchOptions(
                    query: "(",
                    usesRegularExpression: true
                )
            )
            XCTFail("Expected invalid regex error")
        } catch let error as ProjectTextSearchError {
            guard case .invalidRegularExpression = error else {
                return XCTFail("Expected invalid regex error")
            }
        }
    }

    func testSearchReportsResultLimit() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        needle
        needle
        needle
        """.write(to: rootURL.appending(path: "Notes.txt"), atomically: true, encoding: .utf8)

        let response = try await makeSearchService().search(
            projectURL: rootURL,
            options: ProjectTextSearchOptions(query: "needle"),
            resultLimit: 2
        )

        XCTAssertEqual(response.results.count, 2)
        XCTAssertTrue(response.summary.didHitResultLimit)
    }

    func testSearchReportsMissingExecutable() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        do {
            _ = try await ProjectTextSearchService(executableURL: nil).search(
                projectURL: rootURL,
                options: ProjectTextSearchOptions(query: "needle")
            )
            XCTFail("Expected missing executable error")
        } catch let error as ProjectTextSearchError {
            XCTAssertEqual(error, .searchExecutableNotFound)
        }
    }

    func testSearchReportsLaunchFailureForMissingExecutablePath() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        do {
            _ = try await ProjectTextSearchService(
                executableURL: URL(filePath: "/tmp/ruri-missing-rg-executable")
            ).search(
                projectURL: rootURL,
                options: ProjectTextSearchOptions(query: "needle")
            )
            XCTFail("Expected missing executable error")
        } catch let error as ProjectTextSearchError {
            XCTAssertEqual(error, .searchExecutableNotFound)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSearchService() throws -> ProjectTextSearchService {
        guard let executableURL = ripgrepExecutableURL() else {
            throw XCTSkip("ripgrep is not available in PATH.")
        }

        return ProjectTextSearchService(executableURL: executableURL)
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
