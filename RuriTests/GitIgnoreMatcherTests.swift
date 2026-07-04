//
//  GitIgnoreMatcherTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class GitIgnoreMatcherTests: XCTestCase {
    private let fileManager = FileManager.default

    func testNegatedFileCannotReincludeFromIgnoredDirectory() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        build/
        !build/Keep.swift
        """.write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: rootURL.appending(path: "build"), withIntermediateDirectories: false)
        let keptURL = rootURL.appending(path: "build/Keep.swift")
        try "keep".write(to: keptURL, atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(keptURL, isDirectory: false))
    }

    func testNegatedFileCanReincludeWhenOnlyDescendantsAreIgnored() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        build/**
        !build/Keep.swift
        """.write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(at: rootURL.appending(path: "build"), withIntermediateDirectories: false)
        let buildURL = rootURL.appending(path: "build")
        let keptURL = rootURL.appending(path: "build/Keep.swift")
        let generatedURL = rootURL.appending(path: "build/Generated.swift")
        try "keep".write(to: keptURL, atomically: true, encoding: .utf8)
        try "generated".write(to: generatedURL, atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertFalse(matcher.isIgnored(buildURL, isDirectory: true))
        XCTAssertFalse(matcher.isIgnoredBySelfOrAncestor(keptURL, isDirectory: false))
        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(generatedURL, isDirectory: false))
    }

    func testNestedGitIgnoreOverridesParentRules() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let sourcesURL = rootURL.appending(path: "Sources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sourcesURL, withIntermediateDirectories: false)
        try "*.log\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try """
        !debug.log
        *.tmp
        """.write(to: sourcesURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        let debugURL = sourcesURL.appending(path: "debug.log")
        let scratchURL = sourcesURL.appending(path: "scratch.tmp")
        let rootLogURL = rootURL.appending(path: "debug.log")
        try "debug".write(to: debugURL, atomically: true, encoding: .utf8)
        try "scratch".write(to: scratchURL, atomically: true, encoding: .utf8)
        try "root".write(to: rootLogURL, atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertFalse(matcher.isIgnoredBySelfOrAncestor(debugURL, isDirectory: false))
        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(scratchURL, isDirectory: false))
        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(rootLogURL, isDirectory: false))
    }

    func testAnchoredDirectoryPatternOnlyMatchesAtBaseDirectory() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let rootBuildURL = rootURL.appending(path: "Build", directoryHint: .isDirectory)
        let nestedBuildURL = rootURL.appending(path: "Sources/Build", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootBuildURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nestedBuildURL, withIntermediateDirectories: true)
        try "/Build/\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(rootBuildURL, isDirectory: true))
        XCTAssertFalse(matcher.isIgnoredBySelfOrAncestor(nestedBuildURL, isDirectory: true))
    }

    func testUnanchoredDirectoryPatternMatchesNestedDirectories() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        let nestedBuildURL = rootURL.appending(path: "Sources/Build", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: nestedBuildURL, withIntermediateDirectories: true)
        try "Build/\n".write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(nestedBuildURL, isDirectory: true))
    }

    func testBracketGlobAndEscapedLeadingCharacters() throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        file[0-9].tmp
        \\#literal
        \\!literal
        """.write(to: rootURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        let numberedURL = rootURL.appending(path: "file7.tmp")
        let namedURL = rootURL.appending(path: "fileA.tmp")
        let hashURL = rootURL.appending(path: "#literal")
        let bangURL = rootURL.appending(path: "!literal")
        try "numbered".write(to: numberedURL, atomically: true, encoding: .utf8)
        try "named".write(to: namedURL, atomically: true, encoding: .utf8)
        try "hash".write(to: hashURL, atomically: true, encoding: .utf8)
        try "bang".write(to: bangURL, atomically: true, encoding: .utf8)

        var matcher = GitIgnoreMatcher(rootURL: rootURL)

        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(numberedURL, isDirectory: false))
        XCTAssertFalse(matcher.isIgnoredBySelfOrAncestor(namedURL, isDirectory: false))
        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(hashURL, isDirectory: false))
        XCTAssertTrue(matcher.isIgnoredBySelfOrAncestor(bangURL, isDirectory: false))
    }

    private func makeTemporaryDirectory() throws -> URL {
        try TestSupport.makeTemporaryDirectory(fileManager: fileManager)
    }
}
