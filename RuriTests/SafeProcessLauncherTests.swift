//
//  SafeProcessLauncherTests.swift
//  ruriTests
//

import Foundation
import XCTest
@testable import ruri

final class SafeProcessLauncherTests: XCTestCase {
    func testObjectiveCExceptionIsConvertedToSwiftError() throws {
        do {
            try SafeProcessLauncher.catchObjectiveCExceptionForTesting {
                NSException(
                    name: NSExceptionName("RuriTestException"),
                    reason: "process launch exception",
                    userInfo: nil
                ).raise()
            }
            XCTFail("Expected Objective-C exception to be converted.")
        } catch let error as ProcessLaunchError {
            XCTAssertTrue(error.localizedDescription.contains("process launch exception"))
        }
    }

    func testTerminateWithEscalationKillsProcessIgnoringSIGTERM() throws {
        let directoryURL = try TestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let scriptURL = directoryURL.appending(path: "ignore-term")
        try """
        #!/bin/sh
        trap '' TERM
        sleep 60
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path(percentEncoded: false)
        )

        let process = Process()
        process.executableURL = scriptURL
        try SafeProcessLauncher.run(process)

        let start = ContinuousClock.now
        SafeProcessLauncher.terminateWithEscalation(process, gracePeriod: 0.3)

        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(start.duration(to: .now), .seconds(10))
    }

    func testMissingExecutableIsReportedAsLaunchError() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/tmp/ruri-missing-executable")

        do {
            try SafeProcessLauncher.run(process)
            XCTFail("Expected missing executable error.")
        } catch let error as ProcessLaunchError {
            XCTAssertTrue(error.localizedDescription.contains("not executable"))
        }
    }
}
