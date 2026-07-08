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

    func testHeapLimitScalesWithPhysicalMemory() {
        XCTAssertEqual(JavaResolverHeapLimit.megabytes(physicalMemoryBytes: 8 * 1_073_741_824), 2048)
        XCTAssertEqual(JavaResolverHeapLimit.xmxArgument(physicalMemoryBytes: 8 * 1_073_741_824), "-Xmx2048m")
    }

    func testHeapLimitClampsToBounds() {
        XCTAssertEqual(JavaResolverHeapLimit.megabytes(physicalMemoryBytes: 2 * 1_073_741_824), 1024)
        XCTAssertEqual(JavaResolverHeapLimit.megabytes(physicalMemoryBytes: 0), 1024)
        XCTAssertEqual(JavaResolverHeapLimit.megabytes(physicalMemoryBytes: 64 * 1_073_741_824), 4096)
        XCTAssertEqual(JavaResolverHeapLimit.megabytes(physicalMemoryBytes: .max), 4096)
    }

    func testResolverRestartsAfterOutOfMemoryExit() async throws {
        let markerPath = temporaryDirectoryURL.appending(path: "oom-happened").path(percentEncoded: false)
        let executableURL = try makeFakeResolverExecutable(
            script: """
            #!/bin/sh
            if [ ! -f "\(markerPath)" ]; then
              touch "\(markerPath)"
              IFS= read -r line
              id=$(printf '%s\\n' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
              printf '{"id":"%s","payload":null,"error":"Java symbol resolver ran out of memory while indexing symbols."}\\n' "$id"
              exit 3
            fi
            while IFS= read -r line; do
              id=$(printf '%s\\n' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
              printf '{"id":"%s","payload":null,"error":"ok-restarted"}\\n' "$id"
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
            XCTFail("Expected the out-of-memory error.")
        } catch let error as JavaSymbolResolverError {
            // エラー応答行の処理とexit(3)の終了ハンドラは競合するが、どちらの
            // 経路のメッセージにも "ran out of memory" が含まれる。
            XCTAssertTrue(error.message.contains("ran out of memory"), error.message)
        }

        // 旧プロセスの終了通知が処理されるタイミングは非決定的で、直後の要求は
        // もう一度メモリ不足エラーになり得る。保証は「その後の要求で回復する」
        // ことなので、回復まで短時間リトライして検証する。
        var recoveredMessage: String?
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            do {
                _ = try await client.resolve(Self.makeRequest())
                XCTFail("Expected an error envelope from the fake resolver.")
                break
            } catch let error as JavaSymbolResolverError {
                if error.message == "ok-restarted" {
                    recoveredMessage = error.message
                    break
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(recoveredMessage, "ok-restarted")

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
