//
//  SymbolNavigationServiceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

@MainActor
final class SymbolNavigationServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testKotlinUsageJumpsToIndexedClassDefinition() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceDirectoryURL = rootURL.appending(path: "src/main/kotlin/example", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = sourceDirectoryURL.appending(path: "Source.kt")
        let targetURL = sourceDirectoryURL.appending(path: "Target.kt")
        let sourceText = "package example\nfun main() { Target().run() }\n"
        let targetText = "package example\nclass Target { fun run() {} }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try targetText.write(to: targetURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let usageOffset = (sourceText as NSString).range(of: "Target").location
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageOffset
            ),
            openDocuments: []
        )

        guard case .implementation(let target) = resolution else {
            return XCTFail("Expected symbol implementation target.")
        }

        XCTAssertEqual(target.url, targetURL.standardizedFileURL)
        XCTAssertEqual(target.name, "Target")
        XCTAssertTrue(NSEqualRanges(target.range.nsRange, (targetText as NSString).range(of: "Target")))
    }

    func testHoverTargetForResolvedUsageReturnsSourceIdentifierRange() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let targetURL = rootURL.appending(path: "Target.kt")
        let sourceText = "fun main() { Target() }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try "class Target\n".write(to: targetURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let usageRange = (sourceText as NSString).range(of: "Target")
        let hoverTarget = await service.resolveHoverTarget(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageRange.location
            ),
            openDocuments: []
        )

        XCTAssertEqual(
            hoverTarget?.sourceRange,
            TextRange(location: usageRange.location, length: usageRange.length)
        )
    }

    func testHoverTargetForDefinitionDoesNotRequireUsages() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let sourceText = "class Lonely\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let definitionRange = (sourceText as NSString).range(of: "Lonely")
        let hoverTarget = await service.resolveHoverTarget(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: definitionRange.location
            ),
            openDocuments: []
        )

        XCTAssertEqual(
            hoverTarget?.sourceRange,
            TextRange(location: definitionRange.location, length: definitionRange.length)
        )
    }

    func testHoverTargetReturnsNilForUnresolvedUsageAndNonIdentifier() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let sourceText = "fun main() { Missing() }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let missingOffset = (sourceText as NSString).range(of: "Missing").location
        let unresolvedTarget = await service.resolveHoverTarget(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: missingOffset
            ),
            openDocuments: []
        )
        let whitespaceTarget = await service.resolveHoverTarget(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: (sourceText as NSString).range(of: " ").location
            ),
            openDocuments: []
        )

        XCTAssertNil(unresolvedTarget)
        XCTAssertNil(whitespaceTarget)
    }

    func testJavaImportPrefersImportedClassDefinition() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let appURL = rootURL.appending(path: "src/main/java/app", directoryHint: .isDirectory)
        let serviceURL = rootURL.appending(path: "src/main/java/service", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: serviceURL, withIntermediateDirectories: true)

        let sourceURL = appURL.appending(path: "Controller.java")
        let targetURL = serviceURL.appending(path: "UserService.java")
        let otherURL = appURL.appending(path: "UserService.java")
        let sourceText = """
        package app;
        import service.UserService;
        class Controller { UserService service; }

        """
        let targetText = "package service;\npublic class UserService {}\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try targetText.write(to: targetURL, atomically: true, encoding: .utf8)
        try "package app;\nclass UserService {}\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let usageOffset = (sourceText as NSString).range(of: "UserService").location
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageOffset
            ),
            openDocuments: []
        )

        guard case .implementation(let target) = resolution else {
            return XCTFail("Expected imported symbol implementation target.")
        }

        XCTAssertEqual(target.url, targetURL.standardizedFileURL)
    }

    func testDeclarationBuildsUsagesFromUnsavedOpenDocumentText() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let savedText = "class Target\nfun main() { Target() }\n"
        let unsavedText = "class Target\nfun main() { Target().edited() }\n"
        try savedText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let declarationOffset = (unsavedText as NSString).range(of: "Target").location
        let usageRange = (unsavedText as NSString).range(
            of: "Target",
            options: [],
            range: NSRange(location: declarationOffset + 1, length: (unsavedText as NSString).length - declarationOffset - 1)
        )
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: unsavedText,
                utf16Offset: declarationOffset
            ),
            openDocuments: [SymbolNavigationOpenDocument(url: sourceURL, text: unsavedText)]
        )

        guard case .references(let targets) = resolution else {
            return XCTFail("Expected usage targets.")
        }

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].url, sourceURL.standardizedFileURL)
        XCTAssertTrue(NSEqualRanges(targets[0].range.nsRange, usageRange))
    }

    func testSaveStyleSingleFileUpdateChangesDefinitionTarget() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let targetURL = rootURL.appending(path: "Target.kt")
        let sourceText = "fun main() { NewTarget() }\n"
        let oldTargetText = "class OldTarget\n"
        let newTargetText = "class NewTarget\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try oldTargetText.write(to: targetURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        await service.updateFile(projectURL: rootURL, fileURL: targetURL, text: newTargetText)

        let usageOffset = (sourceText as NSString).range(of: "NewTarget").location
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageOffset
            ),
            openDocuments: []
        )

        guard case .implementation(let target) = resolution else {
            return XCTFail("Expected updated symbol target.")
        }

        XCTAssertEqual(target.url, targetURL.standardizedFileURL)
        XCTAssertEqual(target.name, "NewTarget")
    }

    func testIndexSkipsBuildDirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let buildURL = rootURL.appending(path: "build/generated", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: buildURL, withIntermediateDirectories: true)
        let sourceURL = rootURL.appending(path: "Source.kt")
        let generatedURL = buildURL.appending(path: "Generated.kt")
        let sourceText = "fun main() { Generated() }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try "class Generated\n".write(to: generatedURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        let usageOffset = (sourceText as NSString).range(of: "Generated").location
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageOffset
            ),
            openDocuments: []
        )

        XCTAssertNil(resolution)
    }

    func testRefreshRemovesSymbolsWhenDirectoryIsDeleted() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let targetDirectoryURL = rootURL.appending(path: "pkg", directoryHint: .isDirectory)
        let targetURL = targetDirectoryURL.appending(path: "Target.kt")
        let sourceText = "fun main() { Target() }\n"
        try fileManager.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)
        try "class Target\n".write(to: targetURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        try fileManager.removeItem(at: targetDirectoryURL)
        await service.refreshChangedFiles(
            projectURL: rootURL,
            changedPaths: [targetDirectoryURL.path(percentEncoded: false)]
        )

        let usageOffset = (sourceText as NSString).range(of: "Target").location
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageOffset
            ),
            openDocuments: []
        )

        XCTAssertNil(resolution)
    }

    func testRefreshChangedFilesCanSkipStartingMissingIndex() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        try "class Source\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()

        await service.refreshChangedFiles(
            projectURL: rootURL,
            changedPaths: [sourceURL.path(percentEncoded: false)],
            startIndexingIfMissing: false
        )

        XCTAssertEqual(service.currentStatus(for: rootURL), .inactive)
    }

    func testRefreshChangedFilesUpdatesExistingIndexWhenStartIsDisabled() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Source.kt")
        let targetURL = rootURL.appending(path: "Target.kt")
        let sourceText = "fun main() { Target() }\n"
        try sourceText.write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = SymbolNavigationService()
        service.startIndexing(projectURL: rootURL)
        try await waitForReady(service, projectURL: rootURL)

        try "class Target\n".write(to: targetURL, atomically: true, encoding: .utf8)
        await service.refreshChangedFiles(
            projectURL: rootURL,
            changedPaths: [targetURL.path(percentEncoded: false)],
            startIndexingIfMissing: false
        )

        let usageOffset = (sourceText as NSString).range(of: "Target").location
        let resolution = await service.resolveImplementationOrReferences(
            SymbolNavigationRequest(
                projectURL: rootURL,
                fileURL: sourceURL,
                text: sourceText,
                utf16Offset: usageOffset
            ),
            openDocuments: []
        )

        guard case .implementation(let target) = resolution else {
            return XCTFail("Expected refreshed symbol implementation target.")
        }

        XCTAssertEqual(target.url, targetURL.standardizedFileURL)
    }

    private func waitForReady(
        _ service: SymbolNavigationService,
        projectURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<50 {
            if case .ready = service.currentStatus(for: projectURL) {
                return
            }

            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for symbol index readiness.", file: file, line: line)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
