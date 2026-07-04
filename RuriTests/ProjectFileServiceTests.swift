//
//  ProjectFileServiceTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class ProjectFileServiceTests: XCTestCase {
    private let fileManager = FileManager.default

    func testLoadDirectorySortsDirectoriesFirstShowsHiddenItemsAndSkipsRuriMetadata() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL.appending(path: "Tests"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: "Sources"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: ".ruri"), withIntermediateDirectories: false)
        try "readme".write(to: rootURL.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try "app".write(to: rootURL.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "hidden".write(to: rootURL.appending(path: ".secret"), atomically: true, encoding: .utf8)

        let nodes = try await ProjectFileService().loadDirectory(at: rootURL)

        let names = nodes.map(\.name)
        XCTAssertEqual(Array(names.prefix(2)), ["Sources", "Tests"])
        XCTAssertTrue(names.contains(".secret"))
        XCTAssertEqual(Set(names), Set(["Sources", "Tests", "App.swift", "README.md", ".secret"]))
        XCTAssertTrue(nodes[0].isDirectory)
        XCTAssertNil(nodes[0].children)
        XCTAssertFalse(nodes[0].isExpanded)
    }

    func testLoadDirectoryMarksRootGitIgnoredItems() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        *.log
        Build/
        !keep.log
        """.write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        let buildURL = rootURL.appending(path: "Build")
        try fileManager.createDirectory(at: buildURL, withIntermediateDirectories: false)
        try "generated".write(to: buildURL.appending(path: "Generated.swift"), atomically: true, encoding: .utf8)
        try "debug".write(to: rootURL.appending(path: "debug.log"), atomically: true, encoding: .utf8)
        try "keep".write(to: rootURL.appending(path: "keep.log"), atomically: true, encoding: .utf8)

        let rootNodes = try await ProjectFileService().loadDirectory(
            at: rootURL,
            projectRootURL: rootURL
        )
        let buildChildren = try await ProjectFileService().loadDirectory(
            at: buildURL,
            projectRootURL: rootURL
        )

        XCTAssertTrue(try XCTUnwrap(rootNodes.first { $0.name == "Build" }).isIgnored)
        XCTAssertTrue(try XCTUnwrap(rootNodes.first { $0.name == "debug.log" }).isIgnored)
        XCTAssertFalse(try XCTUnwrap(rootNodes.first { $0.name == "keep.log" }).isIgnored)
        XCTAssertFalse(try XCTUnwrap(rootNodes.first { $0.name == ".gitignore" }).isIgnored)
        XCTAssertTrue(try XCTUnwrap(buildChildren.first { $0.name == "Generated.swift" }).isIgnored)
    }

    func testLoadDirectoryAppliesNestedGitIgnoreFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourcesURL = rootURL.appending(path: "Sources")
        try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: false)
        try """
        Generated.swift
        *.log
        !keep.log
        """.write(to: sourcesURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "app".write(to: sourcesURL.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "generated".write(to: sourcesURL.appending(path: "Generated.swift"), atomically: true, encoding: .utf8)
        try "debug".write(to: sourcesURL.appending(path: "debug.log"), atomically: true, encoding: .utf8)
        try "keep".write(to: sourcesURL.appending(path: "keep.log"), atomically: true, encoding: .utf8)

        let nodes = try await ProjectFileService().loadDirectory(
            at: sourcesURL,
            projectRootURL: rootURL
        )

        XCTAssertFalse(try XCTUnwrap(nodes.first { $0.name == "App.swift" }).isIgnored)
        XCTAssertTrue(try XCTUnwrap(nodes.first { $0.name == "Generated.swift" }).isIgnored)
        XCTAssertTrue(try XCTUnwrap(nodes.first { $0.name == "debug.log" }).isIgnored)
        XCTAssertFalse(try XCTUnwrap(nodes.first { $0.name == "keep.log" }).isIgnored)
    }

    func testReadAndWriteUTF8File() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let service = ProjectFileService()

        try await service.writeUTF8File("updated", to: fileURL)
        let text = try await service.readUTF8File(at: fileURL)

        XCTAssertEqual(text, "updated")
    }

    func testWriteUTF8FileReplacingSignatureWritesWhenFileIsUnchanged() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let service = ProjectFileService()
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        let signature = try await service.fileSignature(at: fileURL)

        try await service.writeUTF8File("updated", to: fileURL, replacingSignature: signature)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "updated")
    }

    func testWriteUTF8FileReplacingSignatureThrowsWhenFileChangedExternally() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let service = ProjectFileService()
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)
        let signature = try await service.fileSignature(at: fileURL)

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)

        do {
            try await service.writeUTF8File("updated", to: fileURL, replacingSignature: signature)
            XCTFail("Expected staleFileSignature")
        } catch let error as ProjectFileError {
            XCTAssertEqual(error, .staleFileSignature)
        }
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "external content")
    }

    func testWriteUTF8FileReplacingSignatureExpectsMissingFileForNilSignature() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let service = ProjectFileService()

        try await service.writeUTF8File("recreated", to: fileURL, replacingSignature: nil)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "recreated")

        do {
            try await service.writeUTF8File("again", to: fileURL, replacingSignature: nil)
            XCTFail("Expected staleFileSignature")
        } catch let error as ProjectFileError {
            XCTAssertEqual(error, .staleFileSignature)
        }
    }

    func testWriteUTF8FilePreservesSymlinkAndUpdatesTarget() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let targetURL = rootURL.appending(path: "Target.txt")
        let linkURL = rootURL.appending(path: "Link.txt")
        let service = ProjectFileService()
        try "original".write(to: targetURL, atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        try await service.writeUTF8File("updated", to: linkURL)

        let linkAttributes = try fileManager.attributesOfItem(
            atPath: linkURL.path(percentEncoded: false)
        )
        XCTAssertEqual(linkAttributes[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), "updated")
    }

    func testFileSignatureFollowsSymlinkToRegularFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let targetURL = rootURL.appending(path: "Target.txt")
        let linkURL = rootURL.appending(path: "Link.txt")
        let service = ProjectFileService()
        try "original".write(to: targetURL, atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let signature = try await service.fileSignature(at: linkURL)

        XCTAssertEqual(signature?.fileSize, 8)
    }

    func testFileSignatureReflectsUpdatesAndDeletionForSameURL() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Note.txt")
        let service = ProjectFileService()
        try "original".write(to: fileURL, atomically: true, encoding: .utf8)

        let originalSnapshot = try await service.readUTF8FileSnapshot(at: fileURL)
        XCTAssertEqual(originalSnapshot.signature?.fileSize, 8)

        try "external content".write(to: fileURL, atomically: true, encoding: .utf8)
        let updatedSignature = try await service.fileSignature(at: fileURL)
        XCTAssertEqual(updatedSignature?.fileSize, 16)

        try fileManager.removeItem(at: fileURL)
        let deletedSignature = try await service.fileSignature(at: fileURL)
        XCTAssertNil(deletedSignature)
    }

    func testReadUTF8FileThrowsForInvalidEncoding() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Binary.bin")
        try Data([0xFF]).write(to: fileURL)

        do {
            _ = try await ProjectFileService().readUTF8File(at: fileURL)
            XCTFail("Expected unreadableUTF8File")
        } catch let error as ProjectFileError {
            XCTAssertEqual(error, .unreadableUTF8File)
        }
    }

    func testRenameItemMovesFileToNewName() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Old.txt")
        let service = ProjectFileService()
        try "contents".write(to: sourceURL, atomically: true, encoding: .utf8)

        let renamedURL = try await service.renameItem(at: sourceURL, to: "New.txt")

        XCTAssertFalse(fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)))
        XCTAssertEqual(renamedURL, rootURL.appending(path: "New.txt").standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "contents")
    }

    func testRenameItemThrowsWhenDestinationExists() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Old.txt")
        let existingURL = rootURL.appending(path: "Existing.txt")
        let service = ProjectFileService()
        try "source".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "existing".write(to: existingURL, atomically: true, encoding: .utf8)

        do {
            _ = try await service.renameItem(at: sourceURL, to: "Existing.txt")
            XCTFail("Expected destinationAlreadyExists")
        } catch let error as ProjectFileError {
            XCTAssertEqual(error, .destinationAlreadyExists)
        }
    }

    func testCreateFileCreatesEmptyFileAndReturnsURL() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let createdURL = try await ProjectFileService().createFile(named: "New.txt", in: rootURL)

        XCTAssertEqual(createdURL, rootURL.appending(path: "New.txt").standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: createdURL), Data())
    }

    func testCreateDirectoryCreatesFolder() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let createdURL = try await ProjectFileService().createDirectory(named: "Sources", in: rootURL)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: createdURL.path(percentEncoded: false), isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateFileThrowsWhenDestinationExists() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try "existing".write(to: rootURL.appending(path: "New.txt"), atomically: true, encoding: .utf8)

        do {
            _ = try await ProjectFileService().createFile(named: "New.txt", in: rootURL)
            XCTFail("Expected destinationAlreadyExists")
        } catch let error as ProjectFileError {
            XCTAssertEqual(error, .destinationAlreadyExists)
        }
        XCTAssertEqual(try String(contentsOf: rootURL.appending(path: "New.txt"), encoding: .utf8), "existing")
    }

    func testCreateFileThrowsForInvalidName() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        for invalidName in ["", " ", "a/b", ".", ".."] {
            do {
                _ = try await ProjectFileService().createFile(named: invalidName, in: rootURL)
                XCTFail("Expected invalidFileName for \(invalidName)")
            } catch let error as ProjectFileError {
                XCTAssertEqual(error, .invalidFileName)
            }
        }
    }

    func testTrashItemRemovesFileFromOriginalLocation() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appending(path: "Trashed.txt")
        try "contents".write(to: fileURL, atomically: true, encoding: .utf8)

        try await ProjectFileService().trashItem(at: fileURL)

        XCTAssertFalse(fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    func testTrashItemThrowsForMissingFile() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        do {
            try await ProjectFileService().trashItem(at: rootURL.appending(path: "Missing.txt"))
            XCTFail("Expected an error")
        } catch {
            XCTAssertFalse(error is ProjectFileError)
        }
    }

    func testDuplicateItemUsesCopySuffix() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Note.txt")
        try "contents".write(to: sourceURL, atomically: true, encoding: .utf8)

        let duplicatedURL = try await ProjectFileService().duplicateItem(at: sourceURL)

        XCTAssertEqual(duplicatedURL, rootURL.appending(path: "Note copy.txt").standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: duplicatedURL, encoding: .utf8), "contents")
        XCTAssertTrue(fileManager.fileExists(atPath: sourceURL.path(percentEncoded: false)))
    }

    func testDuplicateItemIncrementsCopyNumberWhenCopyExists() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Note.txt")
        try "contents".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "copy".write(to: rootURL.appending(path: "Note copy.txt"), atomically: true, encoding: .utf8)

        let duplicatedURL = try await ProjectFileService().duplicateItem(at: sourceURL)

        XCTAssertEqual(duplicatedURL, rootURL.appending(path: "Note copy 2.txt").standardizedFileURL)
    }

    func testDuplicateDirectoryCopiesContentsRecursively() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Sources")
        try fileManager.createDirectory(at: sourceURL.appending(path: "Nested"), withIntermediateDirectories: true)
        try "app".write(to: sourceURL.appending(path: "Nested/App.swift"), atomically: true, encoding: .utf8)

        let duplicatedURL = try await ProjectFileService().duplicateItem(at: sourceURL)

        XCTAssertEqual(duplicatedURL, rootURL.appending(path: "Sources copy").standardizedFileURL)
        XCTAssertEqual(
            try String(contentsOf: duplicatedURL.appending(path: "Nested/App.swift"), encoding: .utf8),
            "app"
        )
    }

    func testDuplicateExtensionlessFileUsesCopySuffix() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourceURL = rootURL.appending(path: "Makefile")
        try "all:".write(to: sourceURL, atomically: true, encoding: .utf8)

        let duplicatedURL = try await ProjectFileService().duplicateItem(at: sourceURL)

        XCTAssertEqual(duplicatedURL, rootURL.appending(path: "Makefile copy").standardizedFileURL)
    }

    func testLoadSearchEntriesRecursivelyShowsHiddenItemsAndSkipsMetadataDirectories() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try fileManager.createDirectory(at: rootURL.appending(path: "Sources"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: ".git"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: ".ruri"), withIntermediateDirectories: false)
        try "app".write(to: rootURL.appending(path: "Sources/App.swift"), atomically: true, encoding: .utf8)
        try "readme".write(to: rootURL.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try "hidden".write(to: rootURL.appending(path: ".secret.swift"), atomically: true, encoding: .utf8)
        try "config".write(to: rootURL.appending(path: ".git/Config.swift"), atomically: true, encoding: .utf8)
        try "memo".write(to: rootURL.appending(path: ".ruri/Metadata.swift"), atomically: true, encoding: .utf8)

        let entries = try await makeFileService().loadSearchEntries(at: rootURL)

        XCTAssertEqual(Set(entries.map(\.fileName)), Set(["App.swift", "README.md", ".secret.swift"]))
        XCTAssertEqual(entries.first { $0.fileName == "App.swift" }?.relativeParentPath, "Sources")
        XCTAssertEqual(entries.first { $0.fileName == "README.md" }?.relativeParentPath, "")
    }

    func testLoadSearchEntriesSkipsFilesIgnoredByRootGitIgnore() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        *.log
        Build/
        Docs/*.tmp
        !keep.log
        """.write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: rootURL.appending(path: "Build"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: "Docs"), withIntermediateDirectories: false)
        try fileManager.createDirectory(at: rootURL.appending(path: "Docs/Nested"), withIntermediateDirectories: true)
        try "app".write(to: rootURL.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "generated".write(to: rootURL.appending(path: "Build/Generated.swift"), atomically: true, encoding: .utf8)
        try "debug".write(to: rootURL.appending(path: "debug.log"), atomically: true, encoding: .utf8)
        try "keep".write(to: rootURL.appending(path: "keep.log"), atomically: true, encoding: .utf8)
        try "tmp".write(to: rootURL.appending(path: "Docs/skip.tmp"), atomically: true, encoding: .utf8)
        try "nested".write(to: rootURL.appending(path: "Docs/Nested/keep.tmp"), atomically: true, encoding: .utf8)

        let entries = try await makeFileService().loadSearchEntries(at: rootURL)

        XCTAssertEqual(Set(entries.map(\.fileName)), Set([".gitignore", "App.swift", "keep.log", "keep.tmp"]))
    }

    func testLoadSearchEntriesAppliesNestedGitIgnoreFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourcesURL = rootURL.appending(path: "Sources")
        try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: false)
        try """
        Generated.swift
        *.log
        !keep.log
        """.write(to: sourcesURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try "app".write(to: sourcesURL.appending(path: "App.swift"), atomically: true, encoding: .utf8)
        try "generated".write(to: sourcesURL.appending(path: "Generated.swift"), atomically: true, encoding: .utf8)
        try "debug".write(to: sourcesURL.appending(path: "debug.log"), atomically: true, encoding: .utf8)
        try "keep".write(to: sourcesURL.appending(path: "keep.log"), atomically: true, encoding: .utf8)

        let entries = try await makeFileService().loadSearchEntries(at: rootURL)

        XCTAssertEqual(Set(entries.map(\.fileName)), Set([".gitignore", "App.swift", "keep.log"]))
    }

    func testLoadSearchEntriesReturnsEmptyEntriesForEmptyDirectory() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let entries = try await makeFileService().loadSearchEntries(at: rootURL)

        XCTAssertEqual(entries, [])
    }

    func testLoadSearchEntriesReportsMissingSearchExecutable() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        do {
            _ = try await ProjectFileService(searchExecutableURL: nil).loadSearchEntries(at: rootURL)
            XCTFail("Expected fileSearchExecutableNotFound")
        } catch let error as ProjectFileError {
            XCTAssertEqual(error, .fileSearchExecutableNotFound)
        }
    }

    func testSearchIndexMatchesCaseInsensitivelyAndOrdersPrefixBeforeContains() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/MyApp.swift"),
                    fileName: "MyApp.swift",
                    relativeParentPath: "Sources"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Tests/AppTests.swift"),
                    fileName: "AppTests.swift",
                    relativeParentPath: "Tests"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Sources"
                )
            ]
        )

        let results = index.search(matching: "app")

        XCTAssertEqual(results.map(\.entry.fileName), ["App.swift", "AppTests.swift", "MyApp.swift"])
    }

    func testSearchIndexMatchesRelativePathsCaseInsensitively() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Sources"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Tests/AppTests.swift"),
                    fileName: "AppTests.swift",
                    relativeParentPath: "Tests"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Docs/Guide.md"),
                    fileName: "Guide.md",
                    relativeParentPath: "Docs"
                )
            ]
        )

        let results = index.search(matching: "sources/app")

        XCTAssertEqual(results.map(\.entry.url), [rootURL.appending(path: "Sources/App.swift")])
    }

    func testSearchIndexPrioritizesFileNameMatchesBeforeRelativePathMatches() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "App/Settings.swift"),
                    fileName: "Settings.swift",
                    relativeParentPath: "App"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Generated/App/Notes.swift"),
                    fileName: "Notes.swift",
                    relativeParentPath: "Generated/App"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/MyApp.swift"),
                    fileName: "MyApp.swift",
                    relativeParentPath: "Sources"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Sources"
                )
            ]
        )

        let results = index.search(matching: "app")

        // パスのみマッチ同士は同スコアになり、表示順（fileName順: Notes < Settings）で並ぶ
        XCTAssertEqual(
            results.map(\.entry.url),
            [
                rootURL.appending(path: "Sources/App.swift"),
                rootURL.appending(path: "Sources/MyApp.swift"),
                rootURL.appending(path: "Generated/App/Notes.swift"),
                rootURL.appending(path: "App/Settings.swift")
            ]
        )
    }

    func testSearchIndexSortsSameFileNamesByRelativePathAndLimitsResults() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Tests/View.swift"),
                    fileName: "View.swift",
                    relativeParentPath: "Tests"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/View.swift"),
                    fileName: "View.swift",
                    relativeParentPath: "Sources"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Generated/View.swift"),
                    fileName: "View.swift",
                    relativeParentPath: "Generated"
                )
            ]
        )

        let results = index.search(matching: "view", limit: 2)

        XCTAssertEqual(results.map(\.entry.relativeParentPath), ["Generated", "Sources"])
    }

    func testSearchIndexDeprioritizesTestDirectoryMatches() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Tests/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Tests"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Docs/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Docs"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Sources"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: ""
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Tests/Helpers/AppHelper.swift"),
                    fileName: "AppHelper.swift",
                    relativeParentPath: "Tests/Helpers"
                )
            ]
        )

        let results = index.search(matching: "app")

        XCTAssertEqual(
            results.map(\.entry.url),
            [
                rootURL.appending(path: "App.swift"),
                rootURL.appending(path: "Docs/App.swift"),
                rootURL.appending(path: "Sources/App.swift"),
                rootURL.appending(path: "Tests/App.swift"),
                rootURL.appending(path: "Tests/Helpers/AppHelper.swift")
            ]
        )
    }

    func testSearchIndexKeepsBetterScoredMatchesWhenBroadMatchesExceedLimit() {
        let rootURL = URL(filePath: "/tmp/project")
        var entries = (0..<120).map { index in
            ProjectFileSearchEntry(
                url: rootURL.appending(path: "App/Generated/LowerRank\(index).swift"),
                fileName: "LowerRank\(index).swift",
                relativeParentPath: "App/Generated"
            )
        }
        entries.append(
            ProjectFileSearchEntry(
                url: rootURL.appending(path: "Sources/ZApp.swift"),
                fileName: "ZApp.swift",
                relativeParentPath: "Sources"
            )
        )

        let index = ProjectFileSearchIndex(projectURL: rootURL, entries: entries)

        let results = index.search(matching: "app", limit: 1)

        XCTAssertEqual(results.map(\.entry.fileName), ["ZApp.swift"])
    }

    func testSearchIndexLimitsLargeBroadMatchesInDisplayOrder() {
        let rootURL = URL(filePath: "/tmp/project")
        let entries = (0..<150).map { index in
            ProjectFileSearchEntry(
                url: rootURL.appending(path: "Sources/App\(String(format: "%03d", index)).swift"),
                fileName: "App\(String(format: "%03d", index)).swift",
                relativeParentPath: "Sources"
            )
        }

        let index = ProjectFileSearchIndex(projectURL: rootURL, entries: entries.reversed())

        let results = index.search(matching: "app", limit: 100)

        XCTAssertEqual(results.count, 100)
        XCTAssertEqual(results.first?.entry.fileName, "App000.swift")
        XCTAssertEqual(results.last?.entry.fileName, "App099.swift")
    }

    func testSearchIndexReturnsEntryOnlyOnceWhenFileNameAndPathBothMatch() {
        let rootURL = URL(filePath: "/tmp/project")
        let entry = ProjectFileSearchEntry(
            url: rootURL.appending(path: "App/App.swift"),
            fileName: "App.swift",
            relativeParentPath: "App"
        )
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [entry]
        )

        let results = index.search(matching: "app")

        XCTAssertEqual(results.map(\.entry.url), [entry.url])
    }

    func testSearchIndexMatchesCamelCaseSubsequenceAndReportsFileNameOffsets() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Ruri/Models/ProjectFileSearchIndex.swift"),
                    fileName: "ProjectFileSearchIndex.swift",
                    relativeParentPath: "Ruri/Models"
                ),
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Ruri/Models/ProjectTextSearch.swift"),
                    fileName: "ProjectTextSearch.swift",
                    relativeParentPath: "Ruri/Models"
                )
            ]
        )

        let results = index.search(matching: "pfsi")

        XCTAssertEqual(results.map(\.entry.fileName), ["ProjectFileSearchIndex.swift"])
        // P / F / S / I のcamel境界がハイライト位置として返る
        XCTAssertEqual(results.first?.fileNameMatchOffsets, [0, 7, 11, 17])
        XCTAssertEqual(results.first?.parentPathMatchOffsets, [])
    }

    func testSearchIndexSplitsMatchOffsetsBetweenParentPathAndFileName() {
        let rootURL = URL(filePath: "/tmp/project")
        let index = ProjectFileSearchIndex(
            projectURL: rootURL,
            entries: [
                ProjectFileSearchEntry(
                    url: rootURL.appending(path: "Sources/App.swift"),
                    fileName: "App.swift",
                    relativeParentPath: "Sources"
                )
            ]
        )

        let results = index.search(matching: "sources/app")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.parentPathMatchOffsets, [0, 1, 2, 3, 4, 5, 6])
        // 区切りの "/" は表示文字列に存在しないためオフセットに含まれない
        XCTAssertEqual(results.first?.fileNameMatchOffsets, [0, 1, 2])
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
