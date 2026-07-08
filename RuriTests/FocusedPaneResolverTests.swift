//
//  FocusedPaneResolverTests.swift
//  ruriTests
//

import AppKit
import XCTest
@testable import ruri

final class FocusedPaneResolverTests: XCTestCase {
    func testNonKeyWindowHidesEveryPane() {
        XCTAssertNil(
            FocusedPaneResolver.visiblePane(
                responderKind: .pane(.terminal),
                isFileTreeEngaged: true,
                isFileTreeInlineEditing: true,
                isWindowKey: false
            )
        )
    }

    func testPaneResponderWins() {
        XCTAssertEqual(
            FocusedPaneResolver.visiblePane(
                responderKind: .pane(.editor),
                isFileTreeEngaged: true,
                isFileTreeInlineEditing: false,
                isWindowKey: true
            ),
            .editor
        )
    }

    func testSwiftUIRegionShowsFileTreeOnlyWhenEngaged() {
        XCTAssertEqual(
            FocusedPaneResolver.visiblePane(
                responderKind: .swiftUIRegion,
                isFileTreeEngaged: true,
                isFileTreeInlineEditing: false,
                isWindowKey: true
            ),
            .fileTree
        )
        XCTAssertNil(
            FocusedPaneResolver.visiblePane(
                responderKind: .swiftUIRegion,
                isFileTreeEngaged: false,
                isFileTreeInlineEditing: false,
                isWindowKey: true
            )
        )
    }

    func testTextInputShowsFileTreeOnlyWhileInlineEditing() {
        XCTAssertEqual(
            FocusedPaneResolver.visiblePane(
                responderKind: .textInput,
                isFileTreeEngaged: true,
                isFileTreeInlineEditing: true,
                isWindowKey: true
            ),
            .fileTree
        )
        XCTAssertNil(
            FocusedPaneResolver.visiblePane(
                responderKind: .textInput,
                isFileTreeEngaged: true,
                isFileTreeInlineEditing: false,
                isWindowKey: true
            )
        )
    }

    func testNoResponderYieldsNil() {
        XCTAssertNil(
            FocusedPaneResolver.visiblePane(
                responderKind: .none,
                isFileTreeEngaged: true,
                isFileTreeInlineEditing: false,
                isWindowKey: true
            )
        )
    }

    func testEngagementRetention() {
        XCTAssertTrue(
            FocusedPaneResolver.retainsFileTreeEngagement(
                responderKind: .swiftUIRegion,
                isFileTreeInlineEditing: false
            )
        )
        XCTAssertTrue(
            FocusedPaneResolver.retainsFileTreeEngagement(
                responderKind: .textInput,
                isFileTreeInlineEditing: true
            )
        )
        XCTAssertFalse(
            FocusedPaneResolver.retainsFileTreeEngagement(
                responderKind: .textInput,
                isFileTreeInlineEditing: false
            )
        )
        XCTAssertFalse(
            FocusedPaneResolver.retainsFileTreeEngagement(
                responderKind: .pane(.editor),
                isFileTreeInlineEditing: true
            )
        )
        XCTAssertFalse(
            FocusedPaneResolver.retainsFileTreeEngagement(
                responderKind: .none,
                isFileTreeInlineEditing: true
            )
        )
    }
}

@MainActor
final class PaneFocusStoreClassifyTests: XCTestCase {
    private func makePanes() -> (terminal: NSView, reviewDiffHost: NSView, editorContainer: NSView) {
        (NSView(), NSView(), NSView())
    }

    private func descendant(of parent: NSView) -> NSView {
        let intermediate = NSView()
        let leaf = NSView()
        parent.addSubview(intermediate)
        intermediate.addSubview(leaf)
        return leaf
    }

    func testTerminalDescendantClassifiesAsTerminal() {
        let panes = makePanes()
        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                descendant(of: panes.terminal),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .pane(.terminal)
        )
    }

    func testReviewDiffHostDescendantClassifiesAsReviewDiff() {
        let panes = makePanes()
        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                descendant(of: panes.reviewDiffHost),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .pane(.reviewDiff)
        )
    }

    func testEditorContainerDescendantClassifiesByEditorMode() {
        let panes = makePanes()
        let responder = descendant(of: panes.editorContainer)

        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                responder,
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .pane(.editor)
        )
        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                responder,
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .review
            ),
            .pane(.reviewDiff)
        )
    }

    func testTextViewInsideEditorContainerStaysEditorPane() {
        let panes = makePanes()
        let textView = NSTextView()
        panes.editorContainer.addSubview(textView)

        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                textView,
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .pane(.editor)
        )
    }

    func testTerminalInsideEditorContainerPrefersTerminal() {
        let panes = makePanes()
        panes.editorContainer.addSubview(panes.terminal)

        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                descendant(of: panes.terminal),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .pane(.terminal)
        )
    }

    func testUnregisteredTextResponderClassifiesAsTextInput() {
        let panes = makePanes()

        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                NSTextView(),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .textInput
        )
        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                NSTextField(),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .textInput
        )
    }

    func testUnregisteredPlainViewClassifiesAsSwiftUIRegion() {
        let panes = makePanes()

        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                NSView(),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .swiftUIRegion
        )
    }

    func testNonViewResponderClassifiesAsNone() {
        let panes = makePanes()

        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                NSResponder(),
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .none
        )
        XCTAssertEqual(
            PaneFocusStore.classifyResponder(
                nil,
                terminalPanel: panes.terminal,
                reviewDiffHost: panes.reviewDiffHost,
                editorContainer: panes.editorContainer,
                editorMode: .edit
            ),
            .none
        )
    }
}

private final class FocusableTestView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

final class PaneFocusStoreFocusableDescendantTests: XCTestCase {
    func testFindsNestedFocusableDescendant() {
        let root = NSView()
        let sibling = NSView()
        let intermediate = NSView()
        let focusable = FocusableTestView()
        root.addSubview(sibling)
        root.addSubview(intermediate)
        intermediate.addSubview(focusable)

        XCTAssertTrue(PaneFocusStore.firstFocusableDescendant(of: root) === focusable)
    }

    func testDoesNotReturnRootItself() {
        let root = FocusableTestView()

        XCTAssertNil(PaneFocusStore.firstFocusableDescendant(of: root))
    }

    func testReturnsNilWithoutFocusableDescendant() {
        let root = NSView()
        root.addSubview(NSView())

        XCTAssertNil(PaneFocusStore.firstFocusableDescendant(of: root))
    }
}
