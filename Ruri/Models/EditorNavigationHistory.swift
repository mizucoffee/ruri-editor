//
//  EditorNavigationHistory.swift
//  ruri
//

import CoreGraphics
import Foundation

struct EditorDocumentPlace: Equatable {
    let url: URL
    let selectedRange: NSRange
    let scrollOrigin: CGPoint

    init(
        url: URL,
        selectedRange: NSRange,
        scrollOrigin: CGPoint
    ) {
        self.url = url.standardizedFileURL
        self.selectedRange = selectedRange
        self.scrollOrigin = scrollOrigin
    }

    func hasSamePosition(as other: EditorDocumentPlace) -> Bool {
        FileURLRewriter.urlsMatch(url, other.url)
            && NSEqualRanges(selectedRange, other.selectedRange)
    }

    static func == (lhs: EditorDocumentPlace, rhs: EditorDocumentPlace) -> Bool {
        lhs.hasSamePosition(as: rhs) && lhs.scrollOrigin == rhs.scrollOrigin
    }

    func rewritten(replacing oldURL: URL, with newURL: URL) -> EditorDocumentPlace {
        guard let rewrittenURL = FileURLRewriter.rewrittenURL(
            url,
            replacing: oldURL,
            with: newURL
        ) else {
            return self
        }

        return EditorDocumentPlace(
            url: rewrittenURL,
            selectedRange: selectedRange,
            scrollOrigin: scrollOrigin
        )
    }
}

enum EditorNavigationPlace: Equatable {
    case editor(EditorDocumentPlace)
    case review

    func hasSamePosition(as other: EditorNavigationPlace) -> Bool {
        switch (self, other) {
        case (.editor(let lhs), .editor(let rhs)):
            return lhs.hasSamePosition(as: rhs)
        case (.review, .review):
            return true
        default:
            return false
        }
    }

    func rewritten(replacing oldURL: URL, with newURL: URL) -> EditorNavigationPlace {
        switch self {
        case .editor(let place):
            return .editor(place.rewritten(replacing: oldURL, with: newURL))
        case .review:
            return self
        }
    }
}

struct EditorNavigationHistory {
    private static let maximumPlaceCount = 100

    private(set) var backPlaces: [EditorNavigationPlace] = []
    private(set) var forwardPlaces: [EditorNavigationPlace] = []

    var canGoBack: Bool {
        !backPlaces.isEmpty
    }

    var canGoForward: Bool {
        !forwardPlaces.isEmpty
    }

    mutating func recordNavigation(from place: EditorNavigationPlace) {
        Self.push(place, onto: &backPlaces)
        forwardPlaces = []
    }

    mutating func nextBackCandidate() -> EditorNavigationPlace? {
        backPlaces.popLast()
    }

    mutating func nextForwardCandidate() -> EditorNavigationPlace? {
        forwardPlaces.popLast()
    }

    mutating func recordCurrentPlaceForForward(_ place: EditorNavigationPlace) {
        Self.push(place, onto: &forwardPlaces)
    }

    mutating func recordCurrentPlaceForBack(_ place: EditorNavigationPlace) {
        Self.push(place, onto: &backPlaces)
    }

    mutating func rewriteURLs(replacing oldURL: URL, with newURL: URL) {
        backPlaces = backPlaces.map { $0.rewritten(replacing: oldURL, with: newURL) }
        forwardPlaces = forwardPlaces.map { $0.rewritten(replacing: oldURL, with: newURL) }
    }

    private static func shouldMerge(_ place: EditorNavigationPlace, into places: [EditorNavigationPlace]) -> Bool {
        places.last?.hasSamePosition(as: place) == true
    }

    private static func push(_ place: EditorNavigationPlace, onto places: inout [EditorNavigationPlace]) {
        guard !shouldMerge(place, into: places) else { return }

        places.append(place)

        if places.count > Self.maximumPlaceCount {
            places.removeFirst(places.count - Self.maximumPlaceCount)
        }
    }
}
