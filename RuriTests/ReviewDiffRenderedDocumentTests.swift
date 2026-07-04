//
//  ReviewDiffRenderedDocumentTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

final class ReviewDiffRenderedDocumentTests: XCTestCase {
    func testUnifiedDocumentMapsDiffLinesToSourceRequests() {
        let oldURL = URL(filePath: "/tmp/repo/App.swift")
        let newURL = URL(filePath: "/tmp/repo/App.swift")
        let document = ReviewDiffRenderedDocument.unified(
            file: GitReviewFileDiff(diff: SourceFileDiff(
                oldRelativePath: "App.swift",
                newRelativePath: "App.swift",
                hunks: [
                    SourceDiffHunk(
                        oldStart: 1,
                        oldLineCount: 2,
                        newStart: 1,
                        newLineCount: 3,
                        lines: [
                            SourceDiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "keep"),
                            SourceDiffLine(kind: .deletion, oldLineNumber: 2, newLineNumber: nil, content: "old value"),
                            SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, content: "new value"),
                            SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 3, content: "extra")
                        ]
                    )
                ]
            )),
            oldFileURL: oldURL,
            newFileURL: newURL
        )

        XCTAssertEqual(document.pane, .unified)
        XCTAssertEqual(document.text, "@@ -1,2 +1,3 @@\nkeep\nold value\nnew value\nextra")
        XCTAssertEqual(document.lines.map(\.kind), [.hunkHeader, .context, .deletion, .addition, .addition])
        XCTAssertEqual(document.lines[1].oldLineNumber, 1)
        XCTAssertEqual(document.lines[1].newLineNumber, 1)
        XCTAssertEqual(document.lines[2].oldLineNumber, 2)
        XCTAssertNil(document.lines[2].newLineNumber)
        XCTAssertNil(document.lines[3].oldLineNumber)
        XCTAssertEqual(document.lines[3].newLineNumber, 2)

        let deletionRequest = document.lines[2].navigationRequest(
            atUTF16Location: document.lines[2].contentRange.location + 4
        )
        XCTAssertEqual(deletionRequest?.fileURL, oldURL.standardizedFileURL)
        XCTAssertEqual(deletionRequest?.side, .old)
        XCTAssertEqual(deletionRequest?.lineNumber, 2)
        XCTAssertEqual(deletionRequest?.utf16Column, 4)

        let additionRequest = document.lines[3].navigationRequest(
            atUTF16Location: document.lines[3].contentRange.location + 3
        )
        XCTAssertEqual(additionRequest?.fileURL, newURL.standardizedFileURL)
        XCTAssertEqual(additionRequest?.side, .new)
        XCTAssertEqual(additionRequest?.lineNumber, 2)
        XCTAssertEqual(additionRequest?.utf16Column, 3)
    }

    func testSideBySideDocumentsInsertPlaceholdersForUnpairedRows() {
        let file = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: "App.swift",
            newRelativePath: "App.swift",
            hunks: [
                SourceDiffHunk(
                    oldStart: 1,
                    oldLineCount: 4,
                    newStart: 1,
                    newLineCount: 3,
                    lines: [
                        SourceDiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "keep"),
                        SourceDiffLine(kind: .deletion, oldLineNumber: 2, newLineNumber: nil, content: "old one"),
                        SourceDiffLine(kind: .deletion, oldLineNumber: 3, newLineNumber: nil, content: "old two"),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, content: "new one"),
                        SourceDiffLine(kind: .context, oldLineNumber: 4, newLineNumber: 3, content: "after")
                    ]
                )
            ]
        ))

        let oldDocument = ReviewDiffRenderedDocument.sideBySide(
            file: file,
            side: .old,
            fileURL: URL(filePath: "/tmp/repo/App.swift")
        )
        let newDocument = ReviewDiffRenderedDocument.sideBySide(
            file: file,
            side: .new,
            fileURL: URL(filePath: "/tmp/repo/App.swift")
        )

        XCTAssertEqual(oldDocument.lineCount, newDocument.lineCount)
        XCTAssertEqual(oldDocument.text, "@@ -1,4 +1,3 @@\nkeep\nold one\nold two\nafter")
        XCTAssertEqual(newDocument.text, "@@ -1,4 +1,3 @@\nkeep\nnew one\n \nafter")
        XCTAssertEqual(oldDocument.lines.map(\.kind), [.hunkHeader, .context, .deletion, .deletion, .context])
        XCTAssertEqual(newDocument.lines.map(\.kind), [.hunkHeader, .context, .addition, .placeholder, .context])
        XCTAssertEqual(oldDocument.lines[3].oldLineNumber, 3)
        XCTAssertNil(newDocument.lines[3].sourceLineNumber)
        XCTAssertNil(newDocument.lines[3].navigationRequest(atUTF16Location: newDocument.lines[3].contentRange.location))
    }

    func testLineLookupClampsToRenderedLineForNavigation() {
        let newURL = URL(filePath: "/tmp/repo/App.swift")
        let document = ReviewDiffRenderedDocument.unified(
            file: GitReviewFileDiff(diff: SourceFileDiff(
                oldRelativePath: nil,
                newRelativePath: "App.swift",
                hunks: [
                    SourceDiffHunk(
                        oldStart: 0,
                        oldLineCount: 0,
                        newStart: 1,
                        newLineCount: 1,
                        lines: [
                            SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, content: "emoji 😄 target")
                        ]
                    )
                ]
            )),
            oldFileURL: nil,
            newFileURL: newURL
        )

        let targetLine = document.lines[1]
        let location = targetLine.contentRange.location + ("emoji 😄 " as NSString).length
        let line = document.line(containingUTF16Location: location)
        let request = line?.navigationRequest(atUTF16Location: location)

        XCTAssertEqual(line?.kind, .addition)
        XCTAssertEqual(request?.fileURL, newURL.standardizedFileURL)
        XCTAssertEqual(request?.side, .new)
        XCTAssertEqual(request?.lineNumber, 1)
        XCTAssertEqual(request?.utf16Column, ("emoji 😄 " as NSString).length)
    }

    func testReviewDiffHorizontalScrollNormalizesInitialRulerOrigin() {
        let origin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: -90,
            documentWidth: 800,
            viewportWidth: 400,
            reset: false
        )

        XCTAssertEqual(origin, 0)
    }

    func testReviewDiffHorizontalScrollPreservesUserOrigin() {
        let origin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: 120,
            documentWidth: 800,
            viewportWidth: 400,
            reset: false
        )

        XCTAssertEqual(origin, 120)
    }

    func testReviewDiffHorizontalScrollResetsWhenContentChanges() {
        let origin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: 120,
            documentWidth: 800,
            viewportWidth: 400,
            reset: true
        )

        XCTAssertEqual(origin, 0)
    }

    func testReviewDiffHorizontalScrollClampsWhenContentShrinks() {
        let origin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: 500,
            documentWidth: 640,
            viewportWidth: 400,
            reset: false
        )

        XCTAssertEqual(origin, 240)
    }

    func testReviewDiffHorizontalScrollDoesNotMoveWhenContentFits() {
        let origin = ReviewDiffScrollLayout.normalizedHorizontalOrigin(
            currentOrigin: 80,
            documentWidth: 400,
            viewportWidth: 400,
            reset: false
        )

        XCTAssertEqual(origin, 0)
    }

    func testReviewDiffLayoutIgnoresUnmeasurableViewportWidths() {
        XCTAssertNil(ReviewDiffScrollLayout.measurableViewportWidth(totalWidth: 0, gutterWidth: 120))
        XCTAssertNil(ReviewDiffScrollLayout.measurableViewportWidth(totalWidth: 180, gutterWidth: 120))
        XCTAssertEqual(
            ReviewDiffScrollLayout.measurableViewportWidth(totalWidth: 240, gutterWidth: 120),
            120
        )
    }

    func testReviewDiffLayoutUsesViewportWidthWhenWrapping() {
        let width = ReviewDiffScrollLayout.textWidth(
            viewportWidth: 320,
            documentCodeWidth: 900,
            textInsetWidth: 8,
            wrapLines: true
        )

        XCTAssertEqual(width, 320)
    }

    func testReviewDiffLayoutExpandsToCodeWidthWhenNotWrapping() {
        let width = ReviewDiffScrollLayout.textWidth(
            viewportWidth: 320,
            documentCodeWidth: 900,
            textInsetWidth: 8,
            wrapLines: false
        )

        XCTAssertEqual(width, 916)
    }

    func testReviewDiffLayoutEstimatesDocumentHeightFromLineCount() {
        let height = ReviewDiffScrollLayout.estimatedDocumentHeight(
            lineCount: 12,
            lineHeight: 18,
            textInsetHeight: 6
        )

        XCTAssertEqual(height, 228)
    }

    func testReviewDiffLayoutEstimatesAtLeastOneLine() {
        let height = ReviewDiffScrollLayout.estimatedDocumentHeight(
            lineCount: 0,
            lineHeight: 18,
            textInsetHeight: 6
        )

        XCTAssertEqual(height, 30)
    }

    func testReviewDiffScrollWheelForwardsVerticalGestureToParent() {
        let route = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .gestureBegan,
            deltaX: 2,
            deltaY: -12,
            canScrollHorizontally: true,
            activeRoute: nil
        )

        XCTAssertEqual(route, .parent)
    }

    func testReviewDiffScrollWheelHandlesHorizontalGestureInPane() {
        let route = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .gestureBegan,
            deltaX: -14,
            deltaY: 3,
            canScrollHorizontally: true,
            activeRoute: nil
        )

        XCTAssertEqual(route, .pane)
    }

    func testReviewDiffScrollWheelForwardsHorizontalGestureWhenContentFits() {
        let route = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .gestureBegan,
            deltaX: -14,
            deltaY: 3,
            canScrollHorizontally: false,
            activeRoute: nil
        )

        XCTAssertEqual(route, .parent)
    }

    func testReviewDiffScrollWheelDefersRouteUntilGestureMoves() {
        let began = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .gestureBegan,
            deltaX: 0,
            deltaY: 0,
            canScrollHorizontally: true,
            activeRoute: nil
        )
        let firstMove = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .gestureActive,
            deltaX: -14,
            deltaY: 3,
            canScrollHorizontally: true,
            activeRoute: nil
        )

        XCTAssertNil(began)
        XCTAssertEqual(firstMove, .pane)
    }

    func testReviewDiffScrollWheelKeepsActiveRouteDuringGestureAndMomentum() {
        let active = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .gestureActive,
            deltaX: 1,
            deltaY: -20,
            canScrollHorizontally: true,
            activeRoute: .pane
        )
        let momentum = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .momentum,
            deltaX: 1,
            deltaY: -20,
            canScrollHorizontally: true,
            activeRoute: .pane
        )

        XCTAssertEqual(active, .pane)
        XCTAssertEqual(momentum, .pane)
    }

    func testReviewDiffScrollWheelForwardsUnclaimedMomentumToParent() {
        let route = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .momentum,
            deltaX: -14,
            deltaY: 3,
            canScrollHorizontally: true,
            activeRoute: nil
        )

        XCTAssertEqual(route, .parent)
    }

    func testReviewDiffScrollWheelRoutesDiscreteEventsPerEvent() {
        let horizontal = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .discrete,
            deltaX: -6,
            deltaY: 1,
            canScrollHorizontally: true,
            activeRoute: .parent
        )
        let vertical = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .discrete,
            deltaX: 0,
            deltaY: -6,
            canScrollHorizontally: true,
            activeRoute: .pane
        )
        let idle = ReviewDiffScrollLayout.scrollWheelRoute(
            phase: .discrete,
            deltaX: 0,
            deltaY: 0,
            canScrollHorizontally: true,
            activeRoute: .pane
        )

        XCTAssertEqual(horizontal, .pane)
        XCTAssertEqual(vertical, .parent)
        XCTAssertEqual(idle, .parent)
    }

    func testReviewDiffCanScrollHorizontallyRequiresOverflow() {
        XCTAssertTrue(ReviewDiffScrollLayout.canScrollHorizontally(documentWidth: 900, viewportWidth: 400))
        XCTAssertFalse(ReviewDiffScrollLayout.canScrollHorizontally(documentWidth: 400, viewportWidth: 400))
        XCTAssertFalse(ReviewDiffScrollLayout.canScrollHorizontally(documentWidth: 320, viewportWidth: 400))
    }

    func testSyntaxHighlightsOnlyMatchCurrentRequestID() {
        let key = ReviewDiffLineKey(hunkIndex: 0, lineIndex: 0, side: .new)
        let highlights = ReviewDiffSyntaxHighlights(
            requestID: 10,
            linesByKey: [
                key: ReviewDiffSyntaxLine(segments: [
                    ReviewDiffSyntaxSegment(text: "let", role: .keyword)
                ])
            ],
            themeName: "tree-sitter-light"
        )

        XCTAssertNil(highlights.matching(requestID: 11).line(for: key))
        XCTAssertNotNil(highlights.matching(requestID: 10).line(for: key))
    }

    func testAttributedStringClampsStaleSyntaxHighlightSegments() {
        let file = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: nil,
            newRelativePath: "App.swift",
            hunks: [
                SourceDiffHunk(
                    oldStart: 0,
                    oldLineCount: 0,
                    newStart: 1,
                    newLineCount: 1,
                    lines: [
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, content: "let x = 1")
                    ]
                )
            ]
        ))
        let document = ReviewDiffRenderedDocument.unified(
            file: file,
            oldFileURL: nil,
            newFileURL: URL(filePath: "/tmp/repo/App.swift")
        )
        let key = ReviewDiffLineKey(hunkIndex: 0, lineIndex: 0, side: .new)
        let highlights = ReviewDiffSyntaxHighlights(
            requestID: 1,
            linesByKey: [
                key: ReviewDiffSyntaxLine(segments: [
                    ReviewDiffSyntaxSegment(text: String(repeating: "x", count: 100), role: .keyword)
                ])
            ],
            themeName: "tree-sitter-light"
        )

        let attributedString = ReviewDiffAttributedStringBuilder.attributedString(
            for: document,
            syntaxHighlights: highlights
        )

        XCTAssertEqual(attributedString.string, document.text)
    }
}
