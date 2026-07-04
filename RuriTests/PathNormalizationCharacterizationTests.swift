//
//  PathNormalizationCharacterizationTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

// Characterization tests for path normalization (AGENT_EXPERIENCE.md H3).
// FileURLRewriter is the single implementation: the URL variant for URL inputs
// and the String variant for raw file-system event paths (which must not
// round-trip through URL(filePath:)). The store and watcher sections pin the
// call-site behavior that used to live in private copies, so future changes to
// the shared helpers surface here.
@MainActor
final class PathNormalizationCharacterizationTests: XCTestCase {
    private let fileManager = FileManager.default

    // TestSupport.makeTemporaryDirectory returns a directory URL whose raw
    // path(percentEncoded:) carries a trailing slash; trim it so expected
    // values can be built by string concatenation.
    private func directoryPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    // MARK: - FileURLRewriter.normalizedPath (canonical helper)

    func testNormalizedPathStripsTrailingSlashes() {
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/tmp/a/")), "/tmp/a")
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/tmp/a//")), "/tmp/a")
    }

    func testNormalizedPathKeepsRootSlash() {
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/")), "/")
    }

    func testNormalizedPathCollapsesRedundantComponentsLexically() {
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "//x")), "/x")
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/a/./b")), "/a/b")
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/a/../b")), "/b")
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/a/b/../../c")), "/c")
    }

    func testNormalizedPathPreservesCaseAndSpaces() {
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/A/B")), "/A/B")
        XCTAssertEqual(FileURLRewriter.normalizedPath(URL(filePath: "/tmp/my file")), "/tmp/my file")
    }

    func testNormalizedPathStripsPrivatePrefixOnlyForExistingPaths() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let privateExistingURL = URL(filePath: "/private" + rootPath)
        let privateMissingURL = URL(filePath: "/private" + rootPath + "/missing.txt")

        XCTAssertEqual(FileURLRewriter.normalizedPath(privateExistingURL), rootPath)
        XCTAssertEqual(
            FileURLRewriter.normalizedPath(privateMissingURL),
            "/private" + rootPath + "/missing.txt"
        )
    }

    func testNormalizedPathDoesNotResolveSymlinks() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let targetURL = rootURL.appending(path: "target")
        let linkURL = rootURL.appending(path: "link")
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: false)
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        XCTAssertEqual(
            FileURLRewriter.normalizedPath(linkURL),
            directoryPath(rootURL) + "/link"
        )
        XCTAssertFalse(FileURLRewriter.urlsMatch(linkURL, targetURL))
    }

    // MARK: - FileURLRewriter.normalizedPath (String variant for raw event paths)

    func testStringNormalizedPathStripsTrailingSlashesAndDotComponents() {
        XCTAssertEqual(FileURLRewriter.normalizedPath("/tmp/a/"), "/tmp/a")
        XCTAssertEqual(FileURLRewriter.normalizedPath("/tmp/a//"), "/tmp/a")
        XCTAssertEqual(FileURLRewriter.normalizedPath("/"), "/")
        XCTAssertEqual(FileURLRewriter.normalizedPath("//x"), "/x")
        XCTAssertEqual(FileURLRewriter.normalizedPath("/a/./b"), "/a/b")
        XCTAssertEqual(FileURLRewriter.normalizedPath("/a/../b"), "/b")
    }

    func testStringNormalizedPathKeepsRelativePathsUnresolved() {
        XCTAssertEqual(FileURLRewriter.normalizedPath("a/b"), "a/b")
        XCTAssertEqual(FileURLRewriter.normalizedPath("a/../b"), "a/../b")
        XCTAssertEqual(FileURLRewriter.normalizedPath("./a"), "a")
        XCTAssertEqual(FileURLRewriter.normalizedPath(""), "")
        XCTAssertEqual(FileURLRewriter.normalizedPath("."), ".")
    }

    func testUrlsMatchIgnoresTrailingSlashButNotCase() {
        XCTAssertTrue(FileURLRewriter.urlsMatch(URL(filePath: "/tmp/a/"), URL(filePath: "/tmp/a")))
        XCTAssertFalse(FileURLRewriter.urlsMatch(URL(filePath: "/tmp/a"), URL(filePath: "/tmp/A")))
    }

    func testRewrittenURLBoundaries() {
        let oldRoot = URL(filePath: "/tmp/root")
        let newRoot = URL(filePath: "/tmp/new")

        XCTAssertEqual(
            FileURLRewriter.rewrittenURL(URL(filePath: "/tmp/root"), replacing: oldRoot, with: newRoot),
            URL(filePath: "/tmp/new").standardizedFileURL
        )
        XCTAssertEqual(
            FileURLRewriter.rewrittenURL(URL(filePath: "/tmp/root/a/b.swift"), replacing: oldRoot, with: newRoot),
            URL(filePath: "/tmp/new/a/b.swift").standardizedFileURL
        )
        XCTAssertNil(
            FileURLRewriter.rewrittenURL(URL(filePath: "/tmp/other/a.swift"), replacing: oldRoot, with: newRoot)
        )
        XCTAssertNil(
            FileURLRewriter.rewrittenURL(URL(filePath: "/tmp/root2/a.swift"), replacing: oldRoot, with: newRoot)
        )
        XCTAssertEqual(
            FileURLRewriter.rewrittenURL(URL(filePath: "/tmp/root/a.swift"), replacing: URL(filePath: "/tmp/root/"), with: newRoot),
            URL(filePath: "/tmp/new/a.swift").standardizedFileURL
        )
    }

    // MARK: - Store call sites (isDescendantOrSame) via .git/info/exclude side effect

    private typealias StoreSaveAction = (URL, URL?) async throws -> Void

    private var storeSaveActions: [(name: String, save: StoreSaveAction)] {
        [
            ("WorktreeInitializationStore", { metadataDirectoryURL, repositoryRootURL in
                try await WorktreeInitializationStore().save(
                    WorktreeInitializationDocument(initializationCommand: "echo ok"),
                    metadataDirectoryURL: metadataDirectoryURL,
                    repositoryRootURL: repositoryRootURL
                )
            }),
            ("WorktreeMetadataStore", { metadataDirectoryURL, repositoryRootURL in
                try await WorktreeMetadataStore().saveMemo(
                    "memo",
                    forBranch: "main",
                    metadataDirectoryURL: metadataDirectoryURL,
                    repositoryRootURL: repositoryRootURL
                )
            }),
            ("RunConfigurationStore", { metadataDirectoryURL, repositoryRootURL in
                try await RunConfigurationStore().save(
                    RunConfigurationDocument(),
                    metadataDirectoryURL: metadataDirectoryURL,
                    repositoryRootURL: repositoryRootURL
                )
            })
        ]
    }

    private func makeRepositoryRoot(in baseURL: URL, name: String) throws -> URL {
        let rootURL = baseURL.appending(path: name, directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: rootURL.appending(path: ".git/info", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return rootURL
    }

    private func excludeContainsRuriLine(at rootURL: URL) -> Bool {
        let excludeURL = rootURL.appending(path: ".git/info/exclude")
        guard let text = try? String(contentsOf: excludeURL, encoding: .utf8) else {
            return false
        }
        return text.split(whereSeparator: \.isNewline).contains(".ruri/")
    }

    func testStoresWriteExcludeWhenMetadataDirectoryIsInsideRepositoryRoot() async throws {
        let baseURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: baseURL) }

        for (name, save) in storeSaveActions {
            let rootURL = try makeRepositoryRoot(in: baseURL, name: name)
            try await save(rootURL.appending(path: ".ruri", directoryHint: .isDirectory), rootURL)
            XCTAssertTrue(excludeContainsRuriLine(at: rootURL), "\(name) should write exclude for descendant metadata directory")
        }
    }

    func testStoresSkipExcludeWhenMetadataDirectoryIsOutsideRepositoryRoot() async throws {
        let baseURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: baseURL) }

        for (name, save) in storeSaveActions {
            let rootURL = try makeRepositoryRoot(in: baseURL, name: name)
            let outsideURL = baseURL.appending(path: "\(name)-outside", directoryHint: .isDirectory)
            try await save(outsideURL, rootURL)
            XCTAssertFalse(excludeContainsRuriLine(at: rootURL), "\(name) should not write exclude for outside metadata directory")
        }
    }

    func testStoresTreatRepositoryRootItselfAsDescendant() async throws {
        let baseURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: baseURL) }

        for (name, save) in storeSaveActions {
            let rootURL = try makeRepositoryRoot(in: baseURL, name: name)
            try await save(rootURL, rootURL)
            XCTAssertTrue(excludeContainsRuriLine(at: rootURL), "\(name) should treat the root itself as descendant-or-same")
        }
    }

    func testStoresRejectSiblingDirectoryWithCommonPrefix() async throws {
        let baseURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: baseURL) }

        for (name, save) in storeSaveActions {
            let rootURL = try makeRepositoryRoot(in: baseURL, name: "\(name)-repo")
            let siblingURL = baseURL.appending(path: "\(name)-repo2/.ruri", directoryHint: .isDirectory)
            try await save(siblingURL, rootURL)
            XCTAssertFalse(excludeContainsRuriLine(at: rootURL), "\(name) should not match a sibling sharing the root path as string prefix")
        }
    }

    func testStoresResolveParentComponentsInMetadataPath() async throws {
        let baseURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: baseURL) }

        for (name, save) in storeSaveActions {
            let rootURL = try makeRepositoryRoot(in: baseURL, name: name)
            let dottedURL = rootURL.appending(path: "sub/../.ruri", directoryHint: .isDirectory)
            try await save(dottedURL, rootURL)
            XCTAssertTrue(excludeContainsRuriLine(at: rootURL), "\(name) should resolve .. before the descendant check")
        }
    }

    func testStoresAcceptPrivatePrefixedMetadataPath() async throws {
        let baseURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: baseURL) }

        for (name, save) in storeSaveActions {
            let rootURL = try makeRepositoryRoot(in: baseURL, name: name)
            let privateURL = URL(filePath: "/private" + rootURL.path(percentEncoded: false) + "/.ruri")
            try await save(privateURL, rootURL)
            XCTAssertTrue(excludeContainsRuriLine(at: rootURL), "\(name) should match a /private-prefixed metadata directory once it exists")
        }
    }

    // MARK: - ProjectFileWatcher call site (String variant on raw event strings)

    func testWatcherStripsTrailingSlashesFromEventPaths() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: [rootPath + "/Sources/"],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.changedPaths, [rootPath + "/Sources"])
    }

    func testWatcherResolvesParentComponentsInEventPaths() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: [rootPath + "/Sources/../App.kt"],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.changedPaths, [rootPath + "/App.kt"])
    }

    func testWatcherDropsRelativeEventPaths() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let watcher = ProjectFileWatcher { _ in }

        XCTAssertEqual(
            watcher.classifiedChanges(for: ["Sources/App.kt"], rootURLs: [rootURL]),
            []
        )
    }

    func testWatcherMatchesPrivatePrefixedEventPathForExistingFile() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let filePath = rootPath + "/App.kt"
        try "app".write(toFile: filePath, atomically: true, encoding: .utf8)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: ["/private" + filePath],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.changedPaths, [filePath])
    }

    func testWatcherDropsPrivatePrefixedEventPathForMissingFile() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: ["/private" + rootPath + "/Deleted.kt"],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes, [])
    }

    func testWatcherRootMatchingIsCaseSensitive() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let watcher = ProjectFileWatcher { _ in }

        let changes = watcher.classifiedChanges(
            for: [rootPath.uppercased() + "/App.kt"],
            rootURLs: [rootURL]
        )

        XCTAssertEqual(changes, [])
    }

    func testWatcherMetadataClassificationBoundaries() throws {
        let rootURL = try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootPath = directoryPath(rootURL)
        let watcher = ProjectFileWatcher { _ in }

        let gitignoreChanges = watcher.classifiedChanges(for: [rootPath + "/.gitignore"], rootURLs: [rootURL])
        XCTAssertEqual(gitignoreChanges.first?.changedPaths, [rootPath + "/.gitignore"])
        XCTAssertEqual(gitignoreChanges.first?.gitMetadataChangedPaths, [])

        let gitDirectoryChanges = watcher.classifiedChanges(for: [rootPath + "/.git"], rootURLs: [rootURL])
        XCTAssertEqual(gitDirectoryChanges.first?.gitMetadataChangedPaths, [rootPath + "/.git"])
        XCTAssertEqual(gitDirectoryChanges.first?.changedPaths, [])

        XCTAssertEqual(
            watcher.classifiedChanges(for: [rootPath + "/.ruri"], rootURLs: [rootURL]),
            []
        )
        let ruriLookalikeChanges = watcher.classifiedChanges(for: [rootPath + "/.ruri-notes"], rootURLs: [rootURL])
        XCTAssertEqual(ruriLookalikeChanges.first?.changedPaths, [rootPath + "/.ruri-notes"])
    }
}
