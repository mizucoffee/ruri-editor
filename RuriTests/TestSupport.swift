//
//  TestSupport.swift
//  ruriTests
//

import Foundation
import XCTest

enum TestSupport {
    static func makeTemporaryDirectory(
        fileManager: FileManager = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let url = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            XCTFail("Failed to create temporary directory: \(error)", file: file, line: line)
            throw error
        }
        return url.standardizedFileURL
    }

    static func gitExecutableURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = URL(filePath: "/usr/bin/git")
        guard fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) else {
            throw XCTSkip("git executable is not available")
        }

        return url
    }

    @discardableResult
    static func runGit(
        _ arguments: [String],
        in rootURL: URL,
        fileManager: FileManager = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = try gitExecutableURL(fileManager: fileManager)
        process.arguments = arguments
        process.currentDirectoryURL = rootURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8) ?? "git failed"
            XCTFail(message, file: file, line: line)
            return ""
        }

        return String(data: output, encoding: .utf8) ?? ""
    }

    static func initializeRepository(
        at rootURL: URL,
        fileManager: FileManager = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try runGit(["init", "-b", "main"], in: rootURL, fileManager: fileManager, file: file, line: line)
        try runGit(["config", "user.email", "test@example.com"], in: rootURL, fileManager: fileManager, file: file, line: line)
        try runGit(["config", "user.name", "Test"], in: rootURL, fileManager: fileManager, file: file, line: line)
    }
}
