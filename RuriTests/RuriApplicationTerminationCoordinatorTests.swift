//
//  RuriApplicationTerminationCoordinatorTests.swift
//  ruriTests
//

import AppKit
import XCTest
@testable import ruri

@MainActor
final class RuriApplicationTerminationCoordinatorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testAllowsTerminationWhenNoEditorsAreRegistered() async {
        let coordinator = RuriApplicationTerminationCoordinator()

        await Task.yield()

        XCTAssertFalse(coordinator.shouldPromptForQuitConfirmation)
    }

    func testAllowsTerminationWhenEditorHasNoOpenedProject() async {
        let coordinator = RuriApplicationTerminationCoordinator()
        let editor = EditorState(isFileWatchingEnabled: false)

        coordinator.register(editor)
        await Task.yield()

        XCTAssertFalse(coordinator.shouldPromptForQuitConfirmation)
    }

    func testCancelsTerminationWhenOpenedProjectConfirmationIsDeclined() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        var confirmationCount = 0
        let coordinator = RuriApplicationTerminationCoordinator {
            confirmationCount += 1
            return false
        }
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        coordinator.register(editor)

        XCTAssertEqual(coordinator.applicationShouldTerminate(), .terminateCancel)
        XCTAssertEqual(confirmationCount, 1)
    }

    func testAllowsTerminationWhenOpenedProjectConfirmationIsAccepted() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        var confirmationCount = 0
        let coordinator = RuriApplicationTerminationCoordinator {
            confirmationCount += 1
            return true
        }
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        coordinator.register(editor)

        XCTAssertEqual(coordinator.applicationShouldTerminate(), .terminateNow)
        XCTAssertEqual(confirmationCount, 1)
    }

    func testUnregisteredOpenedProjectDoesNotPromptForTermination() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }

        var confirmationCount = 0
        let coordinator = RuriApplicationTerminationCoordinator {
            confirmationCount += 1
            return false
        }
        let editor = EditorState(isFileWatchingEnabled: false)

        await editor.openProject(rootURL)
        coordinator.register(editor)
        coordinator.unregister(editor)

        XCTAssertEqual(coordinator.applicationShouldTerminate(), .terminateNow)
        XCTAssertEqual(confirmationCount, 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
