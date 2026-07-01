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
