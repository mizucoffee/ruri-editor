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

    func testConsecutiveReviewPlacesAreMerged() {
        let editorPlace = place(url: URL(filePath: "/tmp/ruri/First.swift"), location: 10)
        var history = EditorNavigationHistory()

        history.recordNavigation(from: .review)
        history.recordNavigation(from: .review)
        history.recordNavigation(from: editorPlace)
        history.recordNavigation(from: .review)

        XCTAssertEqual(history.backPlaces, [.review, editorPlace, .review])
    }

    func testReviewAndEditorPlacesAreDistinctPositions() {
        let editorPlace = place(url: URL(filePath: "/tmp/ruri/First.swift"), location: 10)

        XCTAssertFalse(EditorNavigationPlace.review.hasSamePosition(as: editorPlace))
        XCTAssertFalse(editorPlace.hasSamePosition(as: .review))
        XCTAssertTrue(EditorNavigationPlace.review.hasSamePosition(as: .review))
    }

    func testRewriteURLsUpdatesEditorPlacesAndKeepsReviewPlaces() {
        let oldURL = URL(filePath: "/tmp/ruri/Old.swift")
        let newURL = URL(filePath: "/tmp/ruri/New.swift")
        var history = EditorNavigationHistory()

        history.recordNavigation(from: place(url: oldURL, location: 10))
        history.recordNavigation(from: .review)
        history.recordCurrentPlaceForForward(place(url: oldURL, location: 20))

        history.rewriteURLs(replacing: oldURL, with: newURL)

        XCTAssertEqual(
            history.backPlaces,
            [place(url: newURL, location: 10), .review]
        )
        XCTAssertEqual(
            history.forwardPlaces,
            [place(url: newURL, location: 20)]
        )
    }

    private func place(url: URL, location: Int) -> EditorNavigationPlace {
        .editor(
            EditorDocumentPlace(
                url: url,
                selectedRange: NSRange(location: location, length: 0),
                scrollOrigin: CGPoint(x: 0, y: location)
            )
        )
    }
}
