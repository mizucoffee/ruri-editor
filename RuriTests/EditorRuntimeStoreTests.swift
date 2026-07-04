//
//  EditorRuntimeStoreTests.swift
//  ruriTests
//

import AppKit
import XCTest
@testable import ruri

@MainActor
final class EditorRuntimeStoreTests: XCTestCase {
    func testDocumentRuntimesUseDistinctUndoManagers() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let firstTab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let secondTab = makeTab(url: URL(filePath: "/tmp/ruri/Second.swift"), text: "let message = \"日本語\"\n")
        let firstRuntime = store.runtime(
            workspaceID: workspaceID,
            tab: firstTab,
            session: EditorDocumentSession()
        )
        let secondRuntime = store.runtime(
            workspaceID: workspaceID,
            tab: secondTab,
            session: EditorDocumentSession()
        )
        let firstTextView = try textView(from: firstRuntime)
        let secondTextView = try textView(from: secondRuntime)

        XCTAssertNotNil(firstTextView.undoManager)
        XCTAssertNotNil(secondTextView.undoManager)
        XCTAssertFalse(firstTextView.undoManager === secondTextView.undoManager)
    }

    func testRuntimeIsReusedForSameWorkspaceDocument() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let session = EditorDocumentSession()
        let firstRuntime = store.runtime(workspaceID: workspaceID, tab: tab, session: session)
        let reusedRuntime = store.runtime(workspaceID: workspaceID, tab: tab, session: session)

        XCTAssertTrue(firstRuntime === reusedRuntime)
        XCTAssertTrue(try textView(from: firstRuntime).undoManager === textView(from: reusedRuntime).undoManager)
    }

    func testExternalTextSyncCanOptIntoFirstResponderUpdate() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "original")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [], backing: .buffered, defer: false)
        window.contentView = runtime.scrollView
        window.makeFirstResponder(textView)

        XCTAssertTrue(window.firstResponder === textView)

        runtime.syncExternalTextIfNeeded("external")
        XCTAssertEqual(textView.string, "original")

        runtime.syncExternalTextIfNeeded("external", allowsFirstResponderUpdate: true)
        XCTAssertEqual(textView.string, "external")
    }

    func testDocumentRuntimeUndoUsesItsOwnUndoManagerAfterTabStyleSwitching() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let firstTab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let secondTab = makeTab(url: URL(filePath: "/tmp/ruri/Second.swift"), text: "let message = \"日本語\"\n")
        let firstRuntime = store.runtime(
            workspaceID: workspaceID,
            tab: firstTab,
            session: EditorDocumentSession()
        )
        let secondRuntime = store.runtime(
            workspaceID: workspaceID,
            tab: secondTab,
            session: EditorDocumentSession()
        )
        let firstTextView = try textView(from: firstRuntime)
        let secondTextView = try textView(from: secondRuntime)

        insert("A", in: firstTextView)
        XCTAssertEqual(firstTextView.string, "let title = \"日本語\"\nA")
        XCTAssertTrue(firstRuntime.undoCommandState.canUndo)

        insert("B", in: secondTextView)
        XCTAssertEqual(secondTextView.string, "let message = \"日本語\"\nB")
        XCTAssertTrue(secondRuntime.undoCommandState.canUndo)

        firstRuntime.performUndo()
        XCTAssertEqual(firstTextView.string, "let title = \"日本語\"\n")
        XCTAssertEqual(secondTextView.string, "let message = \"日本語\"\nB")

        secondRuntime.performUndo()
        XCTAssertEqual(firstTextView.string, "let title = \"日本語\"\n")
        XCTAssertEqual(secondTextView.string, "let message = \"日本語\"\n")
    }

    func testRuntimeTextViewValidatesUndoMenuItems() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let undoSelector = NSSelectorFromString("undo:")
        let undoMenuItem = NSMenuItem(title: "Undo", action: undoSelector, keyEquivalent: "z")

        XCTAssertTrue(textView.responds(to: undoSelector))
        XCTAssertFalse(textView.validateMenuItem(undoMenuItem))

        insert("A", in: textView)
        XCTAssertTrue(textView.validateMenuItem(undoMenuItem))

        textView.perform(undoSelector, with: nil)
        XCTAssertEqual(textView.string, "let title = \"日本語\"\n")
    }

    func testFindQuerySelectsAndCyclesThroughLiteralMatches() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "ruri foo ruri")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.presentFind(showsReplace: false)
        runtime.updateFindQuery("ruri")

        XCTAssertEqual(
            runtime.findState.matches,
            [
                NSRange(location: 0, length: 4),
                NSRange(location: 9, length: 4)
            ]
        )
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 4))

        runtime.selectNextFindMatch()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 4))

        runtime.selectNextFindMatch()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 4))

        runtime.selectPreviousFindMatch()
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 4))
    }

    func testFindCaseSensitivityChangesMatches() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "Ruri ruri RURI")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.presentFind(showsReplace: false)
        runtime.updateFindQuery("ruri")

        XCTAssertEqual(runtime.findState.matches.count, 3)

        runtime.setFindCaseSensitive(true)

        XCTAssertEqual(runtime.findState.matches, [NSRange(location: 5, length: 4)])
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 4))
    }

    func testInvalidRegexFindKeepsTextUnchanged() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "ruri")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.presentFind(showsReplace: false)
        runtime.updateFindQuery("[")
        runtime.setFindUsesRegularExpression(true)

        XCTAssertEqual(textView.string, "ruri")
        XCTAssertTrue(runtime.findState.matches.isEmpty)
        XCTAssertNotNil(runtime.findState.errorMessage)
    }

    func testReplaceSelectedFindMatchRegistersUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let originalText = "ruri foo ruri"
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: originalText)
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.presentFind(showsReplace: true)
        runtime.updateFindQuery("ruri")
        runtime.updateFindReplacement("ruriOS")
        runtime.replaceSelectedFindMatch()

        XCTAssertEqual(textView.string, "ruriOS foo ruri")
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()

        XCTAssertEqual(textView.string, originalText)
    }

    func testRegexReplaceAllUsesCaptureTemplates() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(
            url: URL(filePath: "/tmp/ruri/Notes.txt"),
            text: "name: ruri\nname: tool"
        )
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.presentFind(showsReplace: true)
        runtime.setFindUsesRegularExpression(true)
        runtime.updateFindQuery(#"name: (\w+)"#)
        runtime.updateFindReplacement("value=$1")
        runtime.replaceAllFindMatches()

        XCTAssertEqual(textView.string, "value=ruri\nvalue=tool")
    }

    func testReplaceAllRegistersSingleUndoStep() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let originalText = "a a a"
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: originalText)
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.presentFind(showsReplace: true)
        runtime.updateFindQuery("a")
        runtime.updateFindReplacement("b")
        runtime.replaceAllFindMatches()

        XCTAssertEqual(textView.string, "b b b")
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()

        XCTAssertEqual(textView.string, originalText)
    }

    func testDocumentRuntimeConfiguresLineNumberRuler() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let rulerView = try XCTUnwrap(runtime.scrollView.verticalRulerView)

        XCTAssertTrue(runtime.scrollView.hasVerticalRuler)
        XCTAssertTrue(runtime.scrollView.rulersVisible)
        XCTAssertEqual(rulerView.orientation, .verticalRuler)
        XCTAssertTrue(rulerView.clientView === textView)
        XCTAssertGreaterThanOrEqual(rulerView.requiredThickness, 36)
    }

    func testDocumentRuntimeConfiguresDiffScroller() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "one\ntwo\nthree\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )

        let diffScroller = try diffScroller(from: runtime)

        XCTAssertEqual(diffScroller.diffDecorations, [])
        XCTAssertFalse(diffScroller.isHidden)
    }

    func testUpdatingDiffDecorationsUpdatesDiffScroller() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "one\ntwo\nthree\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let diffScroller = try diffScroller(from: runtime)
        let decorations = [
            EditorDiffDecoration(lineNumber: 2, kind: .modified),
            EditorDiffDecoration(lineNumber: 3, kind: .added)
        ]

        runtime.updateDiffDecorations(decorations)

        XCTAssertEqual(diffScroller.diffDecorations, decorations)
    }

    func testJumpingToDiffMarkerLineSelectsLineStart() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "one\ntwo\nthree\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        runtime.jumpToLine(3)
        pumpMainRunLoop("diff marker line selection") {
            textView.selectedRange() == NSRange(location: 8, length: 0)
        }

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0))
    }

    func testLineNumberRulerWidthExpandsForLargerLineCounts() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "line 1\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let rulerView = try XCTUnwrap(runtime.scrollView.verticalRulerView)
        let initialThickness = rulerView.requiredThickness
        let appendedText = (2...10_000)
            .map { "line \($0)" }
            .joined(separator: "\n")

        insert(appendedText, in: textView)

        XCTAssertGreaterThan(rulerView.requiredThickness, initialThickness)
    }

    func testActivatingRuntimePreservesLineNumberRulerHorizontalInset() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        runtime.scrollView.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        runtime.scrollView.layoutSubtreeIfNeeded()
        runtime.updateLayout()
        let initialHorizontalOrigin = runtime.scrollView.contentView.bounds.origin.x

        XCTAssertLessThan(initialHorizontalOrigin, 0)

        runtime.activate(focusesTextView: false)
        pumpMainRunLoop("line number ruler horizontal inset restoration") {
            runtime.scrollView.contentView.bounds.origin.x == initialHorizontalOrigin
        }

        XCTAssertEqual(runtime.scrollView.contentView.bounds.origin.x, initialHorizontalOrigin)
    }

    func testLineWrappingModeTogglesHorizontalLayout() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "let value = \"long line\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        runtime.scrollView.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        runtime.scrollView.layoutSubtreeIfNeeded()

        runtime.updateLineWrappingMode(.unwrapped)

        XCTAssertTrue(runtime.scrollView.hasHorizontalScroller)
        XCTAssertTrue(textView.isHorizontallyResizable)
        XCTAssertFalse(try XCTUnwrap(textView.textContainer).widthTracksTextView)
        XCTAssertGreaterThan(try XCTUnwrap(textView.textContainer).containerSize.width, 1_000_000)

        runtime.scrollView.contentView.scroll(to: CGPoint(x: 200, y: 0))
        runtime.scrollView.reflectScrolledClipView(runtime.scrollView.contentView)
        XCTAssertEqual(runtime.scrollView.contentView.bounds.origin.x, 200)

        runtime.updateLineWrappingMode(.wrapped)
        pumpMainRunLoop("wrapped layout restoration") {
            runtime.scrollView.contentView.bounds.origin.x < 0 && textView.frame.width < 1_000_000
        }

        XCTAssertFalse(runtime.scrollView.hasHorizontalScroller)
        XCTAssertTrue(runtime.scrollView.horizontalScroller?.isHidden ?? true)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(try XCTUnwrap(textView.textContainer).widthTracksTextView)
        XCTAssertLessThan(runtime.scrollView.contentView.bounds.origin.x, 0)
        XCTAssertLessThan(textView.frame.width, 1_000_000)
        XCTAssertLessThanOrEqual(textView.frame.width, runtime.scrollView.contentSize.width)
    }

    func testChangingLineWrappingModePreservesTextSelectionAndUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "abc")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        insert("d", in: textView)
        let editedText = textView.string
        let selectedRange = NSRange(location: 2, length: 0)
        textView.setSelectedRange(selectedRange)

        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.updateLineWrappingMode(.unwrapped)

        XCTAssertEqual(textView.string, editedText)
        XCTAssertEqual(textView.selectedRange(), selectedRange)
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()

        XCTAssertEqual(textView.string, "abc")
    }

    func testSwiftDocumentRuntimeAppliesSyntaxHighlightAttributes() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let text = """
        import Foundation
        let title = "日本語"

        """
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: text)
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textView.string, text)
        XCTAssertGreaterThan(
            try waitForForegroundColorDescriptions(in: textStorage, minimumCount: 2).count,
            1
        )
    }

    func testJavaDocumentRuntimeHighlightsMoreThanAnnotations() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let text = """
        package demo;

        public class Main extends Base implements Runnable {
            private final String name = "ruri";

            @Override
            public void run() {
                System.out.println(name);
            }
        }

        """
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Main.java"), text: text)
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let textStorage = try XCTUnwrap(textView.textStorage)

        XCTAssertEqual(textView.string, text)
        XCTAssertGreaterThan(
            try waitForForegroundColorDescriptions(
                for: ["public", "String", "\"ruri\"", "run"],
                in: textStorage,
                minimumCount: 2
            ).count,
            1
        )
        XCTAssertGreaterThan(
            try waitForForegroundColorDescriptions(
                for: ["public", "String", "\"ruri\"", "@Override", "run"],
                in: textStorage,
                minimumCount: 3
            ).count,
            2
        )
    }

    func testJavaScriptDocumentRuntimeHighlightsCommonTokenTypes() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let text = """
        const answer = 42;
        // comment
        console.log("ruri");

        """
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/main.js"), text: text)
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textStorage = try XCTUnwrap(try textView(from: runtime).textStorage)

        XCTAssertGreaterThan(
            try waitForForegroundColorDescriptions(
                for: ["const", "42", "// comment", "\"ruri\""],
                in: textStorage,
                minimumCount: 3
            ).count,
            2
        )
    }

    func testTreeSitterRuntimeHighlightsSupportedLanguageSet() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let cases: [(fileName: String, text: String, needles: [String], minimumCount: Int)] = [
            (
                "Main.kt",
                """
                package demo
                class Main(private val name: String) {
                    fun run() {
                        println("hello $name")
                    }
                }

                """,
                ["class", "String", "run", "\"hello $name\""],
                2
            ),
            (
                "build.gradle",
                """
                plugins {
                    id 'application'
                }

                repositories {
                    mavenCentral()
                }

                tasks.register('runApp') {
                    doLast {
                        println 'ruri'
                    }
                }

                """,
                ["plugins", "id", "'application'", "mavenCentral", "'ruri'"],
                2
            ),
            (
                "main.ts",
                """
                type Item = { name: string }
                const answer: number = 42
                console.log("ruri")

                """,
                ["type", "Item", "number", "42", "\"ruri\""],
                2
            ),
            (
                "settings.json",
                """
                {
                  "name": "ruri",
                  "enabled": true,
                  "count": 42
                }

                """,
                ["\"name\"", "\"ruri\"", "true", "42"],
                2
            ),
            (
                "events.jsonl",
                """
                {"name":"created","count":1}
                {"name":"updated","count":2}

                """,
                ["\"created\"", "1", "\"updated\"", "2"],
                2
            ),
            (
                "schema.sql",
                """
                CREATE TABLE users (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL
                );

                SELECT name FROM users WHERE id = 42;

                """,
                ["CREATE", "TABLE", "INTEGER", "SELECT", "42"],
                2
            ),
            (
                "README.md",
                """
                # Ruri

                - `editor`
                - [docs](https://example.com)

                """,
                ["# Ruri", "`editor`", "[docs]", "https://example.com"],
                2
            ),
            (
                "config.yaml",
                """
                name: ruri
                enabled: true
                retries: 3

                """,
                ["name", "ruri", "true", "3"],
                2
            ),
            (
                "style.css",
                """
                .editor {
                    color: #336699;
                    padding: 8px;
                }

                """,
                [".editor", "color", "#336699", "8"],
                2
            ),
            (
                "index.html",
                """
                <main data-state="ready">
                    <h1>Ruri</h1>
                </main>

                """,
                ["main", "data-state", "\"ready\"", "h1"],
                2
            ),
            (
                "document.xml",
                """
                <note priority="high">
                    <title>Ruri</title>
                </note>

                """,
                ["note", "priority", "\"high\"", "title"],
                2
            )
        ]

        for testCase in cases {
            let tab = makeTab(url: URL(filePath: "/tmp/ruri/\(testCase.fileName)"), text: testCase.text)
            let runtime = store.runtime(
                workspaceID: workspaceID,
                tab: tab,
                session: EditorDocumentSession()
            )
            let textStorage = try XCTUnwrap(
                try textView(from: runtime).textStorage,
                "Missing text storage for \(testCase.fileName)"
            )
            let colors = try waitForForegroundColorDescriptions(
                for: testCase.needles,
                in: textStorage,
                minimumCount: testCase.minimumCount
            )

            XCTAssertGreaterThanOrEqual(
                colors.count,
                testCase.minimumCount,
                "Expected \(testCase.fileName) to receive Tree-sitter colors"
            )
        }
    }

    func testSyntaxHighlightingPreservesInitialSelection() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let session = EditorDocumentSession()
        session.selectedRange = NSRange(location: 4, length: 5)
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: session
        )
        let textView = try textView(from: runtime)

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 5))
    }

    func testUnknownFileTypeStillEditsAsPlainText() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.unknown"), text: "plain text\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)

        insert("next", in: textView)

        XCTAssertEqual(textView.string, "plain text\nnext")
        XCTAssertTrue(runtime.undoCommandState.canUndo)
    }

    func testTabInputDefaultsToFourSpacesAndRegistersUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let value = 1\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.insertTab(nil)

        XCTAssertEqual(textView.string, "let value = 1\n    ")
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()
        XCTAssertEqual(textView.string, "let value = 1\n")
    }

    func testSpaceTabInputAdvancesToNextTabStop() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "ab")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        runtime.updateTabInputSetting(EditorTabInputSetting(mode: .spaces, width: 4))
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.insertTab(nil)

        XCTAssertEqual(textView.string, "ab  ")
    }

    func testTabsModeInsertsTabCharacter() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "ab")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        runtime.updateTabInputSetting(EditorTabInputSetting(mode: .tabs, width: 4))
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.insertTab(nil)

        XCTAssertEqual(textView.string, "ab\t")
    }

    func testMultilineTabInputIndentsEachSelectedLine() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo\nthree")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        runtime.updateTabInputSetting(EditorTabInputSetting(mode: .spaces, width: 4))
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        textView.insertTab(nil)

        XCTAssertEqual(textView.string, "    one\n    two\nthree")
        XCTAssertNotEqual(textView.selectedRange().location, NSNotFound)
    }

    func testEmptySelectionCopyCopiesCurrentLineWithTrailingNewline() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        NSPasteboard.general.clearContents()

        textView.copy(nil)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "two\n")
        XCTAssertEqual(textView.string, "one\ntwo")
    }

    func testEmptySelectionLineCopyAndCutValidateMenuItems() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        let copyMenuItem = NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        let cutMenuItem = NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x")

        XCTAssertTrue(textView.validateMenuItem(copyMenuItem))
        XCTAssertTrue(textView.validateMenuItem(cutMenuItem))
    }

    func testSelectionCopyUsesStandardSelectedTextCopy() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 5, length: 2))
        NSPasteboard.general.clearContents()

        textView.copy(nil)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "wo")
        XCTAssertEqual(textView.string, "one\ntwo")
    }

    func testEmptySelectionCutCutsCurrentLineAndRegistersUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo\nthree")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        NSPasteboard.general.clearContents()

        textView.cut(nil)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "two\n")
        XCTAssertEqual(textView.string, "one\nthree")
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()
        XCTAssertEqual(textView.string, "one\ntwo\nthree")
    }

    func testLineClipboardPasteInsertsAboveCurrentLineAndRegistersUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo\nthree")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("alpha\nbeta\n", forType: .string)

        textView.paste(nil)

        XCTAssertEqual(textView.string, "one\nalpha\nbeta\ntwo\nthree")
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()
        XCTAssertEqual(textView.string, "one\ntwo\nthree")
    }

    func testPlainClipboardPasteUsesStandardInsertion() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("plain", forType: .string)

        textView.paste(nil)

        XCTAssertEqual(textView.string, "one\nplaintwo")
    }

    func testClipboardWithMultipleTrailingNewlinesUsesStandardInsertion() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("plain\n\n", forType: .string)

        textView.paste(nil)

        XCTAssertEqual(textView.string, "one\ntplain\n\nwo")
    }

    func testEmptySelectionDeleteDeletesCurrentLineAndRegistersUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo\nthree")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        XCTAssertTrue(runtime.deleteCurrentLinesWhenSelectionIsEmpty())

        XCTAssertEqual(textView.string, "one\nthree")
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()
        XCTAssertEqual(textView.string, "one\ntwo\nthree")
    }

    func testSelectionDeleteFallsBackWhenTextRangeIsSelected() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\ntwo\nthree")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: 2, length: 5))

        XCTAssertFalse(runtime.deleteCurrentLinesWhenSelectionIsEmpty())

        XCTAssertEqual(textView.string, "one\ntwo\nthree")
    }

    func testEmptySelectionDeleteRemovesTrailingEmptyLine() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/Notes.txt"), text: "one\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        XCTAssertTrue(runtime.deleteCurrentLinesWhenSelectionIsEmpty())

        XCTAssertEqual(textView.string, "one")
    }

    func testSyntaxLanguageStateUsesInferredLanguage() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let languageState = runtime.syntaxLanguageState

        XCTAssertEqual(languageState.inferredLanguageName, "swift")
        XCTAssertNil(languageState.overrideLanguageName)
        XCTAssertEqual(languageState.effectiveLanguageName, "swift")
        XCTAssertEqual(languageState.effectiveDisplayName, "Swift")
        XCTAssertTrue(languageState.languageOptions.contains(SyntaxLanguageOption(identifier: "swift", displayName: "Swift")))
    }

    func testSyntaxLanguageOverridePersistsForOpenDocumentRuntime() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let session = EditorDocumentSession()
        let runtime = store.runtime(workspaceID: workspaceID, tab: tab, session: session)

        runtime.setSyntaxLanguageOverride("json")
        let reusedRuntime = store.runtime(workspaceID: workspaceID, tab: tab, session: session)

        XCTAssertTrue(runtime === reusedRuntime)
        XCTAssertEqual(session.syntaxLanguageOverride, "json")
        XCTAssertEqual(reusedRuntime.syntaxLanguageState.overrideLanguageName, "json")
        XCTAssertEqual(reusedRuntime.syntaxLanguageState.effectiveLanguageName, "json")
    }

    func testClearingSyntaxLanguageOverrideRestoresInferredLanguage() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )

        runtime.setSyntaxLanguageOverride("json")
        runtime.setSyntaxLanguageOverride(nil)

        XCTAssertNil(runtime.syntaxLanguageState.overrideLanguageName)
        XCTAssertEqual(runtime.syntaxLanguageState.effectiveLanguageName, "swift")
    }

    func testChangingSyntaxLanguagePreservesTextSelectionAndUndo() throws {
        let store = EditorRuntimeStore()
        let workspaceID = URL(filePath: "/tmp/ruri")
        let tab = makeTab(url: URL(filePath: "/tmp/ruri/First.swift"), text: "let title = \"日本語\"\n")
        let runtime = store.runtime(
            workspaceID: workspaceID,
            tab: tab,
            session: EditorDocumentSession()
        )
        let textView = try textView(from: runtime)
        let selectedRange = NSRange(location: 4, length: 5)
        textView.setSelectedRange(selectedRange)

        runtime.setSyntaxLanguageOverride("json")

        XCTAssertEqual(textView.string, "let title = \"日本語\"\n")
        XCTAssertEqual(textView.selectedRange(), selectedRange)

        insert("A", in: textView)
        XCTAssertTrue(runtime.undoCommandState.canUndo)

        runtime.performUndo()
        XCTAssertEqual(textView.string, "let title = \"日本語\"\n")
    }

    func testCursorPositionCountsLinesAndCharacters() {
        let text = "abc\n日本語\nz"

        XCTAssertEqual(
            EditorDocumentRuntime.cursorPosition(in: text, selectedRange: NSRange(location: 0, length: 0)),
            EditorCursorPosition(line: 1, column: 1)
        )
        XCTAssertEqual(
            EditorDocumentRuntime.cursorPosition(in: text, selectedRange: NSRange(location: 3, length: 0)),
            EditorCursorPosition(line: 1, column: 4)
        )
        XCTAssertEqual(
            EditorDocumentRuntime.cursorPosition(in: text, selectedRange: NSRange(location: 4, length: 0)),
            EditorCursorPosition(line: 2, column: 1)
        )
        XCTAssertEqual(
            EditorDocumentRuntime.cursorPosition(in: text, selectedRange: NSRange(location: 6, length: 0)),
            EditorCursorPosition(line: 2, column: 3)
        )
        XCTAssertEqual(
            EditorDocumentRuntime.cursorPosition(in: text, selectedRange: NSRange(location: text.utf16.count, length: 0)),
            EditorCursorPosition(line: 3, column: 2)
        )
    }

    func testSelectedLineRangesIncludeCaretLineAndSelectedLines() {
        let text = "one\ntwo\nthree\n"

        XCTAssertEqual(
            EditorDocumentRuntime.selectedLineRanges(
                in: text,
                selectedRanges: [NSRange(location: 5, length: 0)]
            ),
            [NSRange(location: 4, length: 4)]
        )
        XCTAssertEqual(
            EditorDocumentRuntime.selectedLineRanges(
                in: text,
                selectedRanges: [NSRange(location: 2, length: 5)]
            ),
            [
                NSRange(location: 0, length: 4),
                NSRange(location: 4, length: 4)
            ]
        )
        XCTAssertEqual(
            EditorDocumentRuntime.selectedLineRanges(
                in: text,
                selectedRanges: [NSRange(location: 0, length: 4)]
            ),
            [NSRange(location: 0, length: 4)]
        )
        XCTAssertEqual(
            EditorDocumentRuntime.selectedLineRanges(
                in: text,
                selectedRanges: [NSRange(location: text.utf16.count, length: 0)]
            ),
            [NSRange(location: text.utf16.count, length: 0)]
        )
    }

    func testSelectedLineRangesHandleEmptyText() {
        XCTAssertEqual(
            EditorDocumentRuntime.selectedLineRanges(
                in: "",
                selectedRanges: [NSRange(location: 0, length: 0)]
            ),
            [NSRange(location: 0, length: 0)]
        )
    }

    private func makeTab(url: URL, text: String) -> EditorTabSnapshot {
        let document = OpenDocument(url: url, text: text, lastSavedText: text)
        let tab = EditorTab(documentID: document.id)

        return EditorTabSnapshot(
            id: tab.id,
            documentID: document.id,
            url: document.url,
            text: document.text,
            lastSavedText: document.lastSavedText,
            hasUserEdited: document.hasUserEdited,
            lastKnownFileSignature: document.lastKnownFileSignature,
            externalStatus: document.externalStatus
        )
    }

    private func textView(from runtime: EditorDocumentRuntime) throws -> NSTextView {
        try XCTUnwrap(runtime.scrollView.documentView as? NSTextView)
    }

    private func diffScroller(from runtime: EditorDocumentRuntime) throws -> EditorDiffScroller {
        try XCTUnwrap(runtime.scrollView.verticalScroller as? EditorDiffScroller)
    }

    private func insert(_ text: String, in textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private func foregroundColorDescriptions(in textStorage: NSTextStorage) -> Set<String> {
        var colors = Set<String>()
        textStorage.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: textStorage.length),
            options: []
        ) { value, _, _ in
            guard let color = value as? NSColor else { return }
            colors.insert(color.description)
        }
        return colors
    }

    private func pumpMainRunLoop(timeout: TimeInterval, until condition: () throws -> Bool) rethrows {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while try !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    private func pumpMainRunLoop(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        until condition: () -> Bool
    ) {
        pumpMainRunLoop(timeout: timeout, until: condition)
        if !condition() {
            XCTFail("Timed out waiting for \(description).", file: file, line: line)
        }
    }

    private func waitForForegroundColorDescriptions(
        in textStorage: NSTextStorage,
        minimumCount: Int,
        timeout: TimeInterval = 5
    ) throws -> Set<String> {
        var colors = foregroundColorDescriptions(in: textStorage)
        pumpMainRunLoop(timeout: timeout) {
            colors = foregroundColorDescriptions(in: textStorage)
            return colors.count >= minimumCount
        }
        return colors
    }

    private func waitForForegroundColorDescriptions(
        for needles: [String],
        in textStorage: NSTextStorage,
        minimumCount: Int,
        timeout: TimeInterval = 5
    ) throws -> Set<String> {
        var colors = try foregroundColorDescriptions(for: needles, in: textStorage)
        try pumpMainRunLoop(timeout: timeout) {
            colors = try foregroundColorDescriptions(for: needles, in: textStorage)
            return colors.count >= minimumCount
        }
        return colors
    }

    private func foregroundColorDescriptions(
        for needles: [String],
        in textStorage: NSTextStorage
    ) throws -> Set<String> {
        var colors = Set<String>()
        for needle in needles {
            let range = (textStorage.string as NSString).range(of: needle)
            XCTAssertNotEqual(range.location, NSNotFound, "Missing token: \(needle)")
            let color = try XCTUnwrap(
                textStorage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor,
                "Missing foreground color for token: \(needle)"
            )
            colors.insert(color.description)
        }
        return colors
    }
}
