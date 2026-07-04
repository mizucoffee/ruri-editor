//
//  JavaSymbolResolverClientTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class JavaSymbolResolverClientTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = try TestSupport.makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    func testResolveThrowsTimeoutWhenProcessNeverResponds() async throws {
        let executableURL = try makeFakeResolverExecutable(
            script: """
            #!/bin/sh
            exec cat > /dev/null
            """
        )
        let client = JavaSymbolResolverClient(
            javaExecutableURL: executableURL,
            jarURL: executableURL,
            timeout: 0.5
        )

        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await client.resolve(Self.makeRequest())
            XCTFail("Expected a timeout error.")
        } catch let error as JavaSymbolResolverError {
            XCTAssertTrue(error.message.contains("timed out"), error.message)
        }
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(5))

        await client.stop()
    }

    func testMalformedResponseLineDoesNotFailPendingRequest() async throws {
        let executableURL = try makeFakeResolverExecutable(
            script: """
            #!/bin/sh
            while IFS= read -r line; do
              id=$(printf '%s\\n' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
              echo 'this line is not json'
              printf '{"id":"%s","payload":null,"error":"boom"}\\n' "$id"
            done
            """
        )
        let client = JavaSymbolResolverClient(
            javaExecutableURL: executableURL,
            jarURL: executableURL,
            timeout: 5
        )

        do {
            _ = try await client.resolve(Self.makeRequest())
            XCTFail("Expected the resolver error envelope.")
        } catch let error as JavaSymbolResolverError {
            XCTAssertEqual(error.message, "boom")
        }

        await client.stop()
    }

    private func makeFakeResolverExecutable(script: String) throws -> URL {
        let url = temporaryDirectoryURL.appending(path: "fake-java")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }

    private static func makeRequest() -> JavaSymbolResolverRequest {
        JavaSymbolResolverRequest(
            command: .resolve,
            projectPath: "/tmp/project",
            filePath: "/tmp/project/Main.java",
            text: "class Main {}",
            utf16Offset: 6,
            openDocuments: [],
            sourceRoots: [],
            sourceFiles: [],
            classpath: [],
            referenceLimit: nil
        )
    }
}
