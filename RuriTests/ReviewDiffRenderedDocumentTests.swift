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

    func testReviewDiffLayoutEstimatesDocumentHeightFromRowCount() {
        let height = ReviewDiffScrollLayout.estimatedDocumentHeight(
            rowCount: 12,
            lineHeight: 18,
            textInsetHeight: 6
        )

        XCTAssertEqual(height, 228)
    }

    func testReviewDiffLayoutEstimatesAtLeastOneRow() {
        let height = ReviewDiffScrollLayout.estimatedDocumentHeight(
            rowCount: 0,
            lineHeight: 18,
            textInsetHeight: 6
        )

        XCTAssertEqual(height, 30)
    }

    func testReviewDiffLayoutSkipsRemeasureForUnchangedSignature() {
        let signature = ReviewDiffScrollLayout.MeasurementSignature(textWidth: 320, wrapLines: true)

        XCTAssertFalse(ReviewDiffScrollLayout.needsRemeasure(
            previous: signature,
            candidate: signature,
            forced: false
        ))
    }

    func testReviewDiffLayoutRemeasuresWhenSignatureChangesOrForced() {
        let signature = ReviewDiffScrollLayout.MeasurementSignature(textWidth: 320, wrapLines: true)

        XCTAssertTrue(ReviewDiffScrollLayout.needsRemeasure(
            previous: nil,
            candidate: signature,
            forced: false
        ))
        XCTAssertTrue(ReviewDiffScrollLayout.needsRemeasure(
            previous: ReviewDiffScrollLayout.MeasurementSignature(textWidth: 480, wrapLines: true),
            candidate: signature,
            forced: false
        ))
        XCTAssertTrue(ReviewDiffScrollLayout.needsRemeasure(
            previous: ReviewDiffScrollLayout.MeasurementSignature(textWidth: 320, wrapLines: false),
            candidate: signature,
            forced: false
        ))
        XCTAssertTrue(ReviewDiffScrollLayout.needsRemeasure(
            previous: signature,
            candidate: signature,
            forced: true
        ))
    }

    func testUnifiedEstimatedChunkRowCountsMatchBuiltDocuments() {
        let file = mixedRunsFile()

        for maxRows in [2, 3, 256, Int.max] {
            let chunks = ReviewDiffRenderedDocument.unifiedDocuments(
                for: file,
                oldFileURL: URL(filePath: "/tmp/repo/App.swift"),
                newFileURL: URL(filePath: "/tmp/repo/App.swift"),
                columnsPerRow: nil,
                maxEstimatedRowsPerDocument: maxRows
            )
            let estimated = ReviewDiffRenderedDocument.unifiedEstimatedChunkRowCounts(
                for: file,
                columnsPerRow: nil,
                maxEstimatedRowsPerDocument: maxRows
            )

            XCTAssertEqual(estimated, chunks.map(\.estimatedRowCount), "maxRows: \(maxRows)")
            // 非折り返しでは推定表示行数 = 論理行数
            XCTAssertEqual(chunks.map(\.estimatedRowCount), chunks.map(\.lineCount), "maxRows: \(maxRows)")
        }
    }

    func testSideBySideEstimatedChunkRowCountsMatchBuiltDocuments() {
        let file = mixedRunsFile()

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
        let estimated = ReviewDiffRenderedDocument.sideBySideEstimatedChunkRowCounts(
            for: file,
            columnsPerRow: nil,
            maxEstimatedRowsPerDocument: Int.max
        )

        XCTAssertEqual(estimated, [oldDocument.lineCount])
        XCTAssertEqual(estimated, [newDocument.lineCount])
    }

    func testUnifiedDocumentsChunkingPreservesContent() {
        let file = mixedRunsFile()
        let full = ReviewDiffRenderedDocument.unified(
            file: file,
            oldFileURL: URL(filePath: "/tmp/repo/App.swift"),
            newFileURL: URL(filePath: "/tmp/repo/App.swift")
        )
        let chunks = ReviewDiffRenderedDocument.unifiedDocuments(
            for: file,
            oldFileURL: URL(filePath: "/tmp/repo/App.swift"),
            newFileURL: URL(filePath: "/tmp/repo/App.swift"),
            columnsPerRow: nil,
            maxEstimatedRowsPerDocument: 2
        )

        XCTAssertTrue(chunks.allSatisfy { $0.lineCount <= 2 })
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.lineCount }, full.lineCount)
        XCTAssertEqual(chunks.flatMap { $0.lines.map(\.kind) }, full.lines.map(\.kind))
        XCTAssertEqual(chunks.map(\.text).joined(separator: "\n"), full.text)
        XCTAssertTrue(chunks.allSatisfy { $0.maximumCodeWidth <= full.maximumCodeWidth })
    }

    func testSideBySideDocumentsChunkBoundariesMatchAcrossSides() {
        let file = mixedRunsFile()
        let oldChunks = ReviewDiffRenderedDocument.sideBySideDocuments(
            for: file,
            side: .old,
            fileURL: URL(filePath: "/tmp/repo/App.swift"),
            columnsPerRow: nil,
            maxEstimatedRowsPerDocument: 3
        )
        let newChunks = ReviewDiffRenderedDocument.sideBySideDocuments(
            for: file,
            side: .new,
            fileURL: URL(filePath: "/tmp/repo/App.swift"),
            columnsPerRow: nil,
            maxEstimatedRowsPerDocument: 3
        )

        XCTAssertEqual(oldChunks.count, newChunks.count)
        XCTAssertEqual(oldChunks.map(\.lineCount), newChunks.map(\.lineCount))
        XCTAssertEqual(
            oldChunks.map(\.estimatedRowCount),
            ReviewDiffRenderedDocument.sideBySideEstimatedChunkRowCounts(
                for: file,
                columnsPerRow: nil,
                maxEstimatedRowsPerDocument: 3
            )
        )
    }

    func testWrappedSideBySideChunkRowCountsUsePairedRowMax() {
        // 非対称な長行: 削除側だけ長い行(20カラム)、追加のみの hunk に長行(30カラム)
        let file = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: "App.swift",
            newRelativePath: "App.swift",
            hunks: [
                SourceDiffHunk(
                    oldStart: 1,
                    oldLineCount: 3,
                    newStart: 1,
                    newLineCount: 2,
                    lines: [
                        SourceDiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, content: "keep"),
                        SourceDiffLine(
                            kind: .deletion,
                            oldLineNumber: 2,
                            newLineNumber: nil,
                            content: String(repeating: "d", count: 20)
                        ),
                        SourceDiffLine(kind: .deletion, oldLineNumber: 3, newLineNumber: nil, content: "old"),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, content: "new")
                    ]
                ),
                SourceDiffHunk(
                    oldStart: 10,
                    oldLineCount: 0,
                    newStart: 9,
                    newLineCount: 1,
                    lines: [
                        SourceDiffLine(
                            kind: .addition,
                            oldLineNumber: nil,
                            newLineNumber: 9,
                            content: String(repeating: "a", count: 30)
                        )
                    ]
                )
            ]
        ))

        // ペア行ごとの max(8カラム/行): hunk1 = header(1) + keep(1) + [d×20|new](3)
        // + [old|欠側](1)、hunk2 = header(1) + [欠側|a×30](4)
        let expectedTotalRows = 1 + 1 + 3 + 1 + 1 + 4

        for maxRows in [4, Int.max] {
            let estimated = ReviewDiffRenderedDocument.sideBySideEstimatedChunkRowCounts(
                for: file,
                columnsPerRow: 8,
                maxEstimatedRowsPerDocument: maxRows
            )
            let oldChunks = ReviewDiffRenderedDocument.sideBySideDocuments(
                for: file,
                side: .old,
                fileURL: nil,
                columnsPerRow: 8,
                maxEstimatedRowsPerDocument: maxRows
            )
            let newChunks = ReviewDiffRenderedDocument.sideBySideDocuments(
                for: file,
                side: .new,
                fileURL: nil,
                columnsPerRow: 8,
                maxEstimatedRowsPerDocument: maxRows
            )

            // count-only 推定と構築済みチャンクの厳密一致(プレースホルダ高の不変条件)
            XCTAssertEqual(estimated, oldChunks.map(\.estimatedRowCount), "maxRows: \(maxRows)")
            XCTAssertEqual(estimated, newChunks.map(\.estimatedRowCount), "maxRows: \(maxRows)")
            // 境界・行数の左右一致
            XCTAssertEqual(oldChunks.map(\.lineCount), newChunks.map(\.lineCount), "maxRows: \(maxRows)")
            XCTAssertEqual(estimated.reduce(0, +), expectedTotalRows, "maxRows: \(maxRows)")
            // 折り返し考慮の推定は論理行数以上
            XCTAssertTrue(
                zip(oldChunks.map(\.estimatedRowCount), oldChunks.map(\.lineCount)).allSatisfy { $0 >= $1 },
                "maxRows: \(maxRows)"
            )
        }

        // ファイル単位プレースホルダ高 = Σ チャンク推定高
        let estimated = ReviewDiffRenderedDocument.sideBySideEstimatedChunkRowCounts(
            for: file,
            columnsPerRow: 8,
            maxEstimatedRowsPerDocument: 4
        )
        let oldChunks = ReviewDiffRenderedDocument.sideBySideDocuments(
            for: file,
            side: .old,
            fileURL: nil,
            columnsPerRow: 8,
            maxEstimatedRowsPerDocument: 4
        )
        XCTAssertEqual(
            ReviewDiffScrollLayout.estimatedChunkedDocumentHeight(
                chunkRowCounts: estimated,
                lineHeight: 18,
                textInsetHeight: 6
            ),
            oldChunks.reduce(0) { height, chunk in
                height + ReviewDiffScrollLayout.estimatedDocumentHeight(
                    rowCount: chunk.estimatedRowCount,
                    lineHeight: 18,
                    textInsetHeight: 6
                )
            }
        )
    }

    func testPairedRowTargetsAndExtraRows() {
        XCTAssertEqual(ReviewDiffScrollLayout.pairedRowTargets([1, 2, 3], [2, 1, 3]), [2, 2, 3])
        // 行数不一致(ドキュメント差し替えの過渡状態)は nil
        XCTAssertNil(ReviewDiffScrollLayout.pairedRowTargets([1, 2], [1, 2, 3]))

        XCTAssertEqual(
            ReviewDiffScrollLayout.extraRows(natural: [1, 2, 3], target: [2, 2, 3]),
            [1, 0, 0]
        )
        // 目標が実測より小さくても負にはならない
        XCTAssertEqual(ReviewDiffScrollLayout.extraRows(natural: [3, 1], target: [2, 2]), [0, 1])
    }

    func testEstimatedChunkedDocumentHeightMatchesPerChunkSum() {
        let lineHeight: CGFloat = 18
        let inset: CGFloat = 6
        let perChunk: (Int) -> CGFloat = { rows in
            ReviewDiffScrollLayout.estimatedDocumentHeight(
                rowCount: rows,
                lineHeight: lineHeight,
                textInsetHeight: inset
            )
        }

        XCTAssertEqual(
            ReviewDiffScrollLayout.estimatedChunkedDocumentHeight(
                chunkRowCounts: [4, 4, 2],
                lineHeight: lineHeight,
                textInsetHeight: inset
            ),
            perChunk(4) + perChunk(4) + perChunk(2)
        )
        XCTAssertEqual(
            ReviewDiffScrollLayout.estimatedChunkedDocumentHeight(
                chunkRowCounts: [3],
                lineHeight: lineHeight,
                textInsetHeight: inset
            ),
            perChunk(3)
        )
    }

    func testSourceDiffLineDisplayColumnCounts() {
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: ""), 1)
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: "abcd"), 4)
        // タブは次の4カラム境界へ: "ab" (2) + tab (→4) + "c" = 5
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: "ab\tc"), 5)
        // 行頭タブは4カラム
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: "\tx"), 5)
        // 東アジア全角は2カラム
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: "あい"), 4)
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: "a漢b"), 4)
    }

    func testSourceDiffLineDisplayCapsLongLines() {
        let cap = SourceDiffLineDisplay.maxRenderedLineUTF16Length
        let short = String(repeating: "x", count: cap)
        XCTAssertEqual(SourceDiffLineDisplay.cappedContent(short), short)

        let long = String(repeating: "x", count: cap + 500)
        let capped = SourceDiffLineDisplay.cappedContent(long)
        XCTAssertEqual(capped.utf16.count, cap + SourceDiffLineDisplay.truncationMarker.utf16.count)
        XCTAssertTrue(capped.hasSuffix(SourceDiffLineDisplay.truncationMarker))
        XCTAssertEqual(SourceDiffLineDisplay.columnCount(of: long), cap + 1)

        // Character 境界を壊さない(サロゲートペアをまたぐ切断をしない)
        let emoji = String(repeating: "😄", count: cap)
        let cappedEmoji = SourceDiffLineDisplay.cappedContent(emoji)
        XCTAssertLessThanOrEqual(cappedEmoji.utf16.count, cap + SourceDiffLineDisplay.truncationMarker.utf16.count)
        XCTAssertFalse(cappedEmoji.unicodeScalars.contains { $0.value == 0xFFFD })
        XCTAssertTrue(cappedEmoji.dropLast().allSatisfy { $0 == "😄" })
    }

    func testBuilderCapsRenderedLineContent() {
        let cap = SourceDiffLineDisplay.maxRenderedLineUTF16Length
        let longContent = String(repeating: "z", count: cap * 3)
        let document = ReviewDiffRenderedDocument.unified(
            file: GitReviewFileDiff(diff: SourceFileDiff(
                oldRelativePath: nil,
                newRelativePath: "long.js",
                hunks: [
                    SourceDiffHunk(
                        oldStart: 0,
                        oldLineCount: 0,
                        newStart: 1,
                        newLineCount: 1,
                        lines: [
                            SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, content: longContent)
                        ]
                    )
                ]
            )),
            oldFileURL: nil,
            newFileURL: URL(filePath: "/tmp/repo/long.js")
        )

        let renderedLine = document.lines[1]
        XCTAssertEqual(
            renderedLine.contentRange.length,
            cap + SourceDiffLineDisplay.truncationMarker.utf16.count
        )
        XCTAssertEqual(NSMaxRange(renderedLine.contentRange), document.text.utf16.count)
        XCTAssertTrue(document.text.hasSuffix(SourceDiffLineDisplay.truncationMarker))
        // ナビゲーション用の元の長さは保持する
        XCTAssertEqual(renderedLine.sourceContentUTF16Length, cap * 3)
        // 幅計測もキャップ後の内容に基づく
        XCTAssertLessThanOrEqual(
            document.maximumCodeWidth,
            ReviewDiffLayout.codeWidth(for: String(repeating: "z", count: cap + 1))
        )
    }

    func testEstimatedWrappedRowsCeilsColumns() {
        XCTAssertEqual(ReviewDiffScrollLayout.estimatedWrappedRows(columns: 1, columnsPerRow: 80), 1)
        XCTAssertEqual(ReviewDiffScrollLayout.estimatedWrappedRows(columns: 80, columnsPerRow: 80), 1)
        XCTAssertEqual(ReviewDiffScrollLayout.estimatedWrappedRows(columns: 81, columnsPerRow: 80), 2)
        XCTAssertEqual(ReviewDiffScrollLayout.estimatedWrappedRows(columns: 240, columnsPerRow: 80), 3)
        // 非折り返し(nil)は常に1
        XCTAssertEqual(ReviewDiffScrollLayout.estimatedWrappedRows(columns: 500, columnsPerRow: nil), 1)
    }

    func testWrappedChunkPlanKeepsChunksWithinRowBudget() {
        // 300カラム ≈ 4表示行(80カラム/行) × 100行 + hunkヘッダ
        let lines = (1...100).map { index in
            SourceDiffLine(
                kind: .addition,
                oldLineNumber: nil,
                newLineNumber: index,
                content: String(repeating: "w", count: 300)
            )
        }
        let file = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: nil,
            newRelativePath: "wrapped.md",
            hunks: [
                SourceDiffHunk(oldStart: 0, oldLineCount: 0, newStart: 1, newLineCount: 100, lines: lines)
            ]
        ))

        let budget = 40
        let chunks = ReviewDiffRenderedDocument.unifiedDocuments(
            for: file,
            oldFileURL: nil,
            newFileURL: URL(filePath: "/tmp/repo/wrapped.md"),
            columnsPerRow: 80,
            maxEstimatedRowsPerDocument: budget
        )

        // 1行が予算を超えない限り、チャンクの推定表示行数は予算内に収まる
        XCTAssertTrue(chunks.allSatisfy { $0.estimatedRowCount <= budget })
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.reduce(0) { $0 + $1.lineCount }, 101)
        // 折り返し考慮の推定は論理行数より大きい
        XCTAssertTrue(chunks.allSatisfy { $0.estimatedRowCount >= $0.lineCount })

        // count-only 推定は構築済みチャンクと厳密一致(プレースホルダ高の不変条件)
        XCTAssertEqual(
            ReviewDiffRenderedDocument.unifiedEstimatedChunkRowCounts(
                for: file,
                columnsPerRow: 80,
                maxEstimatedRowsPerDocument: budget
            ),
            chunks.map(\.estimatedRowCount)
        )
    }

    func testWrappedChunkPlanBoundsSingleOversizedLine() {
        // キャップ後でも1行で予算超になる長行は単独チャンクに隔離され、
        // 推定表示行数はキャップ由来の上限で抑えられる
        let cap = SourceDiffLineDisplay.maxRenderedLineUTF16Length
        let file = GitReviewFileDiff(diff: SourceFileDiff(
            oldRelativePath: nil,
            newRelativePath: "minified.js",
            hunks: [
                SourceDiffHunk(
                    oldStart: 0,
                    oldLineCount: 0,
                    newStart: 1,
                    newLineCount: 2,
                    lines: [
                        SourceDiffLine(
                            kind: .addition,
                            oldLineNumber: nil,
                            newLineNumber: 1,
                            content: String(repeating: "m", count: 50_000)
                        ),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, content: "tail")
                    ]
                )
            ]
        ))

        let chunkRowCounts = ReviewDiffRenderedDocument.unifiedEstimatedChunkRowCounts(
            for: file,
            columnsPerRow: 100,
            maxEstimatedRowsPerDocument: 8
        )

        let cappedRows = (cap + 1 + 99) / 100
        XCTAssertTrue(chunkRowCounts.allSatisfy { $0 <= max(8, cappedRows) })
        XCTAssertEqual(chunkRowCounts.reduce(0, +), 1 + cappedRows + 1)
    }

    func testEstimatedColumnsPerRowAndBucketedPaneWidth() {
        XCTAssertEqual(ReviewDiffScrollLayout.bucketedPaneWidth(1000), 960)
        XCTAssertEqual(ReviewDiffScrollLayout.bucketedPaneWidth(960), 960)
        XCTAssertEqual(ReviewDiffScrollLayout.bucketedPaneWidth(10), 64)

        let columns = ReviewDiffScrollLayout.estimatedColumnsPerRow(
            paneWidth: 960,
            gutterWidth: 150,
            textInsetWidth: 8,
            characterWidth: 7.5
        )
        XCTAssertEqual(columns, Int((960.0 - 150 - 16) / 7.5))
        // 幅が極端に狭くても最低カラム数を確保する
        XCTAssertEqual(
            ReviewDiffScrollLayout.estimatedColumnsPerRow(
                paneWidth: 64,
                gutterWidth: 150,
                textInsetWidth: 8,
                characterWidth: 7.5
            ),
            8
        )
    }

    func testIsNearViewportIncludesOneViewportMargin() {
        let viewport = CGRect(x: 0, y: 0, width: 800, height: 600)

        XCTAssertTrue(ReviewDiffScrollLayout.isNearViewport(
            rowFrame: CGRect(x: 0, y: 100, width: 800, height: 200),
            viewportBounds: viewport
        ))
        XCTAssertTrue(ReviewDiffScrollLayout.isNearViewport(
            rowFrame: CGRect(x: 0, y: -700, width: 800, height: 200),
            viewportBounds: viewport
        ))
        XCTAssertTrue(ReviewDiffScrollLayout.isNearViewport(
            rowFrame: CGRect(x: 0, y: 1100, width: 800, height: 200),
            viewportBounds: viewport
        ))
        XCTAssertFalse(ReviewDiffScrollLayout.isNearViewport(
            rowFrame: CGRect(x: 0, y: -900, width: 800, height: 200),
            viewportBounds: viewport
        ))
        XCTAssertFalse(ReviewDiffScrollLayout.isNearViewport(
            rowFrame: CGRect(x: 0, y: 1300, width: 800, height: 200),
            viewportBounds: viewport
        ))
    }

    func testIsNearViewportDefaultsToVisibleWithoutViewportBounds() {
        XCTAssertTrue(ReviewDiffScrollLayout.isNearViewport(
            rowFrame: CGRect(x: 0, y: 10_000, width: 800, height: 200),
            viewportBounds: nil
        ))
    }

    private func mixedRunsFile() -> GitReviewFileDiff {
        GitReviewFileDiff(diff: SourceFileDiff(
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
                ),
                SourceDiffHunk(
                    oldStart: 10,
                    oldLineCount: 1,
                    newStart: 9,
                    newLineCount: 3,
                    lines: [
                        SourceDiffLine(kind: .context, oldLineNumber: 10, newLineNumber: 9, content: "ctx"),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 10, content: "add one"),
                        SourceDiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 11, content: "add two")
                    ]
                )
            ]
        ))
    }

    func testReviewDiffExpansionPolicyCollapsesViewedFiles() {
        XCTAssertFalse(ReviewDiffExpansionPolicy.initiallyExpanded(
            isViewed: true,
            lineCount: 10,
            fileIndex: 0
        ))
    }

    func testReviewDiffExpansionPolicyExpandsSmallUnviewedFiles() {
        XCTAssertTrue(ReviewDiffExpansionPolicy.initiallyExpanded(
            isViewed: false,
            lineCount: ReviewDiffExpansionPolicy.largeDiffLineThreshold,
            fileIndex: ReviewDiffExpansionPolicy.autoExpandFileLimit - 1
        ))
    }

    func testReviewDiffExpansionPolicyCollapsesLargeDiffs() {
        XCTAssertFalse(ReviewDiffExpansionPolicy.initiallyExpanded(
            isViewed: false,
            lineCount: ReviewDiffExpansionPolicy.largeDiffLineThreshold + 1,
            fileIndex: 0
        ))
    }

    func testReviewDiffExpansionPolicyCollapsesFilesBeyondAutoExpandLimit() {
        XCTAssertFalse(ReviewDiffExpansionPolicy.initiallyExpanded(
            isViewed: false,
            lineCount: 10,
            fileIndex: ReviewDiffExpansionPolicy.autoExpandFileLimit
        ))
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
