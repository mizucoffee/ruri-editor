//
//  EditorNavigationHistoryTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class EditorNavigationHistoryTests: XCTestCase {
    func testConsecutiveDuplicatePlacesAreMergedOnlyAtStackTail() {
        let first = place(url: URL(filePath: "/tmp/ruri/First.swift"), location: 10)
        let second = place(url: URL(filePath: "/tmp/ruri/Second.swift"), location: 20)
        var history = EditorNavigationHistory()

        history.recordNavigation(from: first)
        history.recordNavigation(from: first)
        history.recordNavigation(from: second)
        history.recordNavigation(from: first)

        XCTAssertEqual(history.backPlaces, [first, second, first])
    }

    func testRecordingManualNavigationClearsForwardPlaces() {
        let first = place(url: URL(filePath: "/tmp/ruri/First.swift"), location: 10)
        let second = place(url: URL(filePath: "/tmp/ruri/Second.swift"), location: 20)
        var history = EditorNavigationHistory()

        history.recordCurrentPlaceForForward(second)
        XCTAssertTrue(history.canGoForward)

        history.recordNavigation(from: first)

        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    private func place(url: URL, location: Int) -> EditorNavigationPlace {
        EditorNavigationPlace(
            url: url,
            selectedRange: NSRange(location: location, length: 0),
            scrollOrigin: CGPoint(x: 0, y: location)
        )
    }
}
