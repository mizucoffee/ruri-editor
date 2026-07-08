//
//  ReviewDiffModels.swift
//  ruri
//

import AppKit

enum ReviewDiffSyntaxSide: Hashable, Sendable {
    case old
    case new
}

struct ReviewDiffLineKey: Hashable, Sendable {
    let hunkIndex: Int
    let lineIndex: Int
    let side: ReviewDiffSyntaxSide
}

struct ReviewDiffSyntaxSegment: Equatable, Sendable {
    let text: String
    let role: SyntaxHighlightRole?
}

struct ReviewDiffSyntaxLine: Equatable, Sendable {
    let segments: [ReviewDiffSyntaxSegment]
}

struct ReviewDiffSyntaxHighlights: Sendable {
    static let empty = ReviewDiffSyntaxHighlights(
        requestID: nil,
        linesByKey: [:],
        themeName: "tree-sitter-light"
    )

    let requestID: Int?
    let linesByKey: [ReviewDiffLineKey: ReviewDiffSyntaxLine]
    let themeName: String

    func matching(requestID: Int) -> ReviewDiffSyntaxHighlights {
        self.requestID == requestID ? self : .empty
    }

    func line(for key: ReviewDiffLineKey) -> ReviewDiffSyntaxLine? {
        linesByKey[key]
    }

    func line(
        hunkIndex: Int,
        lineIndex: Int,
        side: ReviewDiffSyntaxSide,
        fallbackSide: ReviewDiffSyntaxSide? = nil
    ) -> ReviewDiffSyntaxLine? {
        line(for: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: side))
            ?? fallbackSide.flatMap {
                line(for: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: $0))
            }
    }
}

struct ReviewDiffRenderedDocument: Equatable {
    enum Pane: Equatable {
        case unified
        case old
        case new

        var gutterColumnCount: Int {
            switch self {
            case .unified:
                2
            case .old, .new:
                1
            }
        }
    }

    static let empty = ReviewDiffRenderedDocument(
        pane: .unified,
        text: " ",
        lines: [
            ReviewDiffRenderedLine(
                kind: .placeholder,
                oldLineNumber: nil,
                newLineNumber: nil,
                marker: " ",
                contentRange: NSRange(location: 0, length: 1),
                sourceContentUTF16Length: 0,
                sourceFileURL: nil,
                navigationSide: nil,
                sourceLineNumber: nil,
                syntaxKey: nil,
                fallbackSyntaxKey: nil
            )
        ],
        maximumCodeWidth: ReviewDiffLayout.codeWidth(for: " "),
        estimatedRowCount: 1
    )

    let pane: Pane
    let text: String
    let lines: [ReviewDiffRenderedLine]
    let maximumCodeWidth: CGFloat
    /// 折り返しを含む推定表示行数(非折り返しでは論理行数と一致)。
    /// プレースホルダ高と実体化直後の高さはこの値から算出して揃える。
    let estimatedRowCount: Int

    var lineCount: Int {
        lines.count
    }

    /// ドキュメントを構築せずに、`unifiedDocuments(for:...)` と同一の分割規則で
    /// 各チャンクの推定表示行数だけを返す(オフスクリーンのファイル単位
    /// プレースホルダ高の算出用)。行の生成順・境界を厳密に一致させること。
    static func unifiedEstimatedChunkRowCounts(
        for file: GitReviewFileDiff,
        columnsPerRow: Int?,
        maxEstimatedRowsPerDocument: Int
    ) -> [Int] {
        ReviewDiffPaneChunkPlan(
            rowsPerLine: unifiedEstimatedRowsPerLine(for: file, columnsPerRow: columnsPerRow),
            maxEstimatedRowsPerDocument: maxEstimatedRowsPerDocument
        ).rowCounts
    }

    /// `sideBySideDocuments(for:...)` と同一の分割規則の count-only 版。
    /// ペア化により old/new 両ペインで常に同じ値になる。
    static func sideBySideEstimatedChunkRowCounts(
        for file: GitReviewFileDiff,
        columnsPerRow: Int?,
        maxEstimatedRowsPerDocument: Int
    ) -> [Int] {
        ReviewDiffPaneChunkPlan(
            rowsPerLine: sideBySideEstimatedRowsPerLine(for: file, columnsPerRow: columnsPerRow),
            maxEstimatedRowsPerDocument: maxEstimatedRowsPerDocument
        ).rowCounts
    }

    static func unified(
        file: GitReviewFileDiff,
        oldFileURL: URL?,
        newFileURL: URL?
    ) -> ReviewDiffRenderedDocument {
        unifiedDocuments(
            for: file,
            oldFileURL: oldFileURL,
            newFileURL: newFileURL,
            columnsPerRow: nil,
            maxEstimatedRowsPerDocument: Int.max
        )[0]
    }

    /// 長いファイルを推定表示行数の予算ごとの複数ドキュメントに分割して返す。
    /// レイヤーバックの巨大ビューはRetinaで約8,000pt(テクスチャ上限16384px)を
    /// 超えた部分の描画が破棄されるため、ペインは分割して積み上げる必要がある。
    /// columnsPerRow を渡すと折り返しを考慮した表示行数で予算を消費する
    /// (nil なら1論理行=1表示行)。境界は ReviewDiffPaneChunkPlan が一意に決める。
    static func unifiedDocuments(
        for file: GitReviewFileDiff,
        oldFileURL: URL?,
        newFileURL: URL?,
        columnsPerRow: Int?,
        maxEstimatedRowsPerDocument: Int
    ) -> [ReviewDiffRenderedDocument] {
        var chunker = ReviewDiffRenderedDocumentChunker(
            pane: .unified,
            plan: ReviewDiffPaneChunkPlan(
                rowsPerLine: unifiedEstimatedRowsPerLine(for: file, columnsPerRow: columnsPerRow),
                maxEstimatedRowsPerDocument: maxEstimatedRowsPerDocument
            )
        )

        for (hunkIndex, hunk) in file.diff.hunks.enumerated() {
            chunker.withBuilder { $0.appendHunkHeader(hunk) }

            for (lineIndex, line) in hunk.lines.enumerated() {
                let syntaxSide = line.unifiedSyntaxSide
                let fallbackSyntaxSide: ReviewDiffSyntaxSide? = syntaxSide == .new ? .old : .new
                let fileURL = line.kind == .deletion ? oldFileURL : newFileURL
                let lineNumber = line.kind == .deletion ? line.oldLineNumber : line.newLineNumber
                chunker.withBuilder {
                    $0.appendCodeLine(
                        content: line.content,
                        kind: ReviewDiffRenderedLine.Kind(line.kind),
                        oldLineNumber: line.oldLineNumber,
                        newLineNumber: line.newLineNumber,
                        marker: line.unifiedMarker,
                        sourceFileURL: fileURL,
                        navigationSide: line.kind == .deletion ? .old : .new,
                        sourceLineNumber: lineNumber,
                        syntaxKey: ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: syntaxSide),
                        fallbackSyntaxKey: fallbackSyntaxSide.map {
                            ReviewDiffLineKey(hunkIndex: hunkIndex, lineIndex: lineIndex, side: $0)
                        }
                    )
                }
            }
        }

        return chunker.finish()
    }

    static func sideBySide(
        file: GitReviewFileDiff,
        side: ReviewDiffSyntaxSide,
        fileURL: URL?
    ) -> ReviewDiffRenderedDocument {
        sideBySideDocuments(
            for: file,
            side: side,
            fileURL: fileURL,
            columnsPerRow: nil,
            maxEstimatedRowsPerDocument: Int.max
        )[0]
    }

    /// `unifiedDocuments(for:...)` の side-by-side 版。old/new は行のペア化により
    /// 追加順序・行数が完全に一致し、rowsPerLine もペア行ごとの max を両サイドで
    /// 共有するため、チャンク境界と推定表示行数は折り返しの有無によらず一致する。
    /// columnsPerRow が nil なら1論理行=1表示行で予算を消費する。
    static func sideBySideDocuments(
        for file: GitReviewFileDiff,
        side: ReviewDiffSyntaxSide,
        fileURL: URL?,
        columnsPerRow: Int?,
        maxEstimatedRowsPerDocument: Int
    ) -> [ReviewDiffRenderedDocument] {
        var chunker = ReviewDiffRenderedDocumentChunker(
            pane: side == .old ? .old : .new,
            plan: ReviewDiffPaneChunkPlan(
                rowsPerLine: sideBySideEstimatedRowsPerLine(for: file, columnsPerRow: columnsPerRow),
                maxEstimatedRowsPerDocument: maxEstimatedRowsPerDocument
            )
        )

        for (hunkIndex, hunk) in file.diff.hunks.enumerated() {
            chunker.withBuilder { $0.appendHunkHeader(hunk) }

            for row in ReviewDiffSideBySideRenderedRow.rows(hunkIndex: hunkIndex, lines: hunk.lines) {
                let indexedLine = side == .old ? row.oldLine : row.newLine
                guard let indexedLine else {
                    chunker.withBuilder { $0.appendPlaceholder() }
                    continue
                }

                let line = indexedLine.line
                let lineNumber = side == .old ? line.oldLineNumber : line.newLineNumber
                chunker.withBuilder {
                    $0.appendCodeLine(
                        content: line.content,
                        kind: ReviewDiffRenderedLine.Kind(line.kind),
                        oldLineNumber: side == .old ? line.oldLineNumber : nil,
                        newLineNumber: side == .new ? line.newLineNumber : nil,
                        marker: line.marker(for: side),
                        sourceFileURL: fileURL,
                        navigationSide: side == .old ? .old : .new,
                        sourceLineNumber: lineNumber,
                        syntaxKey: ReviewDiffLineKey(
                            hunkIndex: indexedLine.hunkIndex,
                            lineIndex: indexedLine.lineIndex,
                            side: side
                        ),
                        fallbackSyntaxKey: nil
                    )
                }
            }
        }

        return chunker.finish()
    }

    /// `unifiedDocuments(for:...)` の行生成(hunkヘッダ1行 + 各行)と同順の
    /// 推定表示行数列。両者の分割境界一致はこの列の同一性に依存する。
    private static func unifiedEstimatedRowsPerLine(
        for file: GitReviewFileDiff,
        columnsPerRow: Int?
    ) -> [Int] {
        var rowsPerLine: [Int] = []
        rowsPerLine.reserveCapacity(file.diff.hunks.reduce(0) { $0 + 1 + $1.lines.count })
        for hunk in file.diff.hunks {
            rowsPerLine.append(1)
            for line in hunk.lines {
                rowsPerLine.append(ReviewDiffScrollLayout.estimatedWrappedRows(
                    columns: line.displayColumnCount,
                    columnsPerRow: columnsPerRow
                ))
            }
        }
        return rowsPerLine
    }

    /// `sideBySideDocuments(for:...)` の行生成(hunkヘッダ1行 + ペア化行)と同順の
    /// 推定表示行数列。折り返し時はペア行ごとに old/new の推定折り返し行数の
    /// 大きい方(欠側は1)を採る。両サイドが同一の列を共有することで
    /// チャンク境界と推定表示行数の左右一致を保つ。
    private static func sideBySideEstimatedRowsPerLine(
        for file: GitReviewFileDiff,
        columnsPerRow: Int?
    ) -> [Int] {
        func estimatedRows(_ indexedLine: ReviewIndexedDiffLine?) -> Int {
            guard let indexedLine else { return 1 }
            return ReviewDiffScrollLayout.estimatedWrappedRows(
                columns: indexedLine.line.displayColumnCount,
                columnsPerRow: columnsPerRow
            )
        }

        var rowsPerLine: [Int] = []
        for hunk in file.diff.hunks {
            rowsPerLine.append(1)
            for row in ReviewDiffSideBySideRenderedRow.rows(hunkIndex: 0, lines: hunk.lines) {
                rowsPerLine.append(max(estimatedRows(row.oldLine), estimatedRows(row.newLine)))
            }
        }
        return rowsPerLine
    }

    func line(containingUTF16Location location: Int) -> ReviewDiffRenderedLine? {
        guard !lines.isEmpty else { return nil }

        let clampedLocation = min(max(0, location), text.utf16.count)
        var lowerBound = 0
        var upperBound = lines.count - 1

        while lowerBound <= upperBound {
            let middle = (lowerBound + upperBound) / 2
            let line = lines[middle]
            let lineStart = line.contentRange.location
            let lineEnd = NSMaxRange(line.contentRange)

            if clampedLocation < lineStart {
                upperBound = middle - 1
            } else if clampedLocation > lineEnd {
                lowerBound = middle + 1
            } else {
                return line
            }
        }

        return lines.last { $0.contentRange.location <= clampedLocation }
    }
}

struct ReviewDiffRenderedLine: Equatable {
    enum Kind: Equatable {
        case hunkHeader
        case context
        case addition
        case deletion
        case placeholder
    }

    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let marker: String
    let contentRange: NSRange
    let sourceContentUTF16Length: Int
    let sourceFileURL: URL?
    let navigationSide: ReviewDiffCodeNavigationSide?
    let sourceLineNumber: Int?
    let syntaxKey: ReviewDiffLineKey?
    let fallbackSyntaxKey: ReviewDiffLineKey?

    var canNavigate: Bool {
        sourceFileURL != nil && navigationSide != nil && sourceLineNumber != nil
    }

    func navigationRequest(atUTF16Location location: Int) -> ReviewDiffCodeNavigationRequest? {
        guard let sourceFileURL,
              let navigationSide,
              let sourceLineNumber else {
            return nil
        }

        let column = min(
            max(0, location - contentRange.location),
            sourceContentUTF16Length
        )
        return ReviewDiffCodeNavigationRequest(
            fileURL: sourceFileURL,
            side: navigationSide,
            lineNumber: sourceLineNumber,
            utf16Column: column
        )
    }
}

private extension ReviewDiffRenderedLine {
    init(
        kind: SourceDiffLine.Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        marker: String,
        contentRange: NSRange,
        sourceContentUTF16Length: Int,
        sourceFileURL: URL?,
        navigationSide: ReviewDiffCodeNavigationSide?,
        sourceLineNumber: Int?,
        syntaxKey: ReviewDiffLineKey?,
        fallbackSyntaxKey: ReviewDiffLineKey?
    ) {
        self.init(
            kind: Kind(kind),
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            marker: marker,
            contentRange: contentRange,
            sourceContentUTF16Length: sourceContentUTF16Length,
            sourceFileURL: sourceFileURL,
            navigationSide: navigationSide,
            sourceLineNumber: sourceLineNumber,
            syntaxKey: syntaxKey,
            fallbackSyntaxKey: fallbackSyntaxKey
        )
    }
}

private extension ReviewDiffRenderedLine.Kind {
    init(_ kind: SourceDiffLine.Kind) {
        switch kind {
        case .context:
            self = .context
        case .addition:
            self = .addition
        case .deletion:
            self = .deletion
        }
    }
}

/// 推定表示行数の予算に基づくチャンク分割計画。ドキュメント構築(チャンカー)と
/// count-only のプレースホルダ推定はどちらも必ずこの計画から境界を得ることで、
/// 「ファイルプレースホルダ高 = Σ チャンク推定高」を厳密に保つ。
struct ReviewDiffPaneChunkPlan: Equatable {
    /// 各チャンクに入る論理行数
    let lineCounts: [Int]
    /// 各チャンクの推定表示行数の合計
    let rowCounts: [Int]

    init(rowsPerLine: [Int], maxEstimatedRowsPerDocument: Int) {
        let budget = max(1, maxEstimatedRowsPerDocument)
        var lineCounts: [Int] = []
        var rowCounts: [Int] = []
        var lines = 0
        var rows = 0

        for lineRows in rowsPerLine {
            if lines > 0, rows + lineRows > budget {
                lineCounts.append(lines)
                rowCounts.append(rows)
                lines = 0
                rows = 0
            }
            lines += 1
            rows += lineRows
        }
        if lines > 0 || lineCounts.isEmpty {
            lineCounts.append(lines)
            rowCounts.append(max(1, rows))
        }

        self.lineCounts = lineCounts
        self.rowCounts = rowCounts
    }
}

/// ReviewDiffPaneChunkPlan の境界に従ってビルダーを切り替え、複数ドキュメントを生成する。
private struct ReviewDiffRenderedDocumentChunker {
    private let pane: ReviewDiffRenderedDocument.Pane
    private let plan: ReviewDiffPaneChunkPlan
    private var builder: ReviewDiffRenderedDocumentBuilder
    private var documents: [ReviewDiffRenderedDocument] = []
    private var lineCount = 0

    init(pane: ReviewDiffRenderedDocument.Pane, plan: ReviewDiffPaneChunkPlan) {
        self.pane = pane
        self.plan = plan
        self.builder = ReviewDiffRenderedDocumentBuilder(pane: pane)
    }

    mutating func withBuilder(_ append: (inout ReviewDiffRenderedDocumentBuilder) -> Void) {
        if documents.count < plan.lineCounts.count, lineCount == plan.lineCounts[documents.count] {
            flushCurrentDocument()
        }
        append(&builder)
        lineCount += 1
    }

    mutating func finish() -> [ReviewDiffRenderedDocument] {
        if lineCount > 0 || documents.isEmpty {
            flushCurrentDocument()
        }
        return documents
    }

    private mutating func flushCurrentDocument() {
        // 追加順序は計画の rowsPerLine と同一のため、通常は必ず計画側の値を使う。
        let estimatedRowCount = documents.count < plan.rowCounts.count
            ? plan.rowCounts[documents.count]
            : max(1, lineCount)
        documents.append(builder.build(estimatedRowCount: estimatedRowCount))
        builder = ReviewDiffRenderedDocumentBuilder(pane: pane)
        lineCount = 0
    }
}

private struct ReviewDiffRenderedDocumentBuilder {
    private(set) var text = ""
    private(set) var lines: [ReviewDiffRenderedLine] = []
    private var maximumCodeWidth = ReviewDiffLayout.codeWidth(for: " ")
    private let pane: ReviewDiffRenderedDocument.Pane

    init(pane: ReviewDiffRenderedDocument.Pane) {
        self.pane = pane
    }

    mutating func appendHunkHeader(_ hunk: SourceDiffHunk) {
        appendLine(
            content: "@@ -\(hunk.oldStart),\(hunk.oldLineCount) +\(hunk.newStart),\(hunk.newLineCount) @@",
            kind: .hunkHeader,
            oldLineNumber: nil,
            newLineNumber: nil,
            marker: " ",
            sourceContentUTF16Length: 0,
            sourceFileURL: nil,
            navigationSide: nil,
            sourceLineNumber: nil,
            syntaxKey: nil,
            fallbackSyntaxKey: nil
        )
    }

    mutating func appendPlaceholder() {
        appendLine(
            content: "",
            kind: .placeholder,
            oldLineNumber: nil,
            newLineNumber: nil,
            marker: " ",
            sourceContentUTF16Length: 0,
            sourceFileURL: nil,
            navigationSide: nil,
            sourceLineNumber: nil,
            syntaxKey: nil,
            fallbackSyntaxKey: nil
        )
    }

    mutating func appendCodeLine(
        content: String,
        kind: ReviewDiffRenderedLine.Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        marker: String,
        sourceFileURL: URL?,
        navigationSide: ReviewDiffCodeNavigationSide?,
        sourceLineNumber: Int?,
        syntaxKey: ReviewDiffLineKey?,
        fallbackSyntaxKey: ReviewDiffLineKey?
    ) {
        appendLine(
            content: content,
            kind: kind,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            marker: marker,
            sourceContentUTF16Length: content.utf16.count,
            sourceFileURL: sourceFileURL,
            navigationSide: navigationSide,
            sourceLineNumber: sourceLineNumber,
            syntaxKey: syntaxKey,
            fallbackSyntaxKey: fallbackSyntaxKey
        )
    }

    mutating func build(estimatedRowCount: Int) -> ReviewDiffRenderedDocument {
        if lines.isEmpty {
            appendPlaceholder()
        }

        return ReviewDiffRenderedDocument(
            pane: pane,
            text: text,
            lines: lines,
            maximumCodeWidth: maximumCodeWidth,
            estimatedRowCount: max(1, estimatedRowCount)
        )
    }

    private mutating func appendLine(
        content: String,
        kind: ReviewDiffRenderedLine.Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        marker: String,
        sourceContentUTF16Length: Int,
        sourceFileURL: URL?,
        navigationSide: ReviewDiffCodeNavigationSide?,
        sourceLineNumber: Int?,
        syntaxKey: ReviewDiffLineKey?,
        fallbackSyntaxKey: ReviewDiffLineKey?
    ) {
        if !text.isEmpty {
            text += "\n"
        }

        // 極端な長行はレイヤー上限(幅・折り返し高の両方)を超えるため表示前に切り詰める。
        let cappedContent = SourceDiffLineDisplay.cappedContent(content)
        let displayContent = cappedContent.isEmpty ? " " : cappedContent
        let start = text.utf16.count
        text += displayContent
        let contentRange = NSRange(location: start, length: displayContent.utf16.count)
        maximumCodeWidth = max(maximumCodeWidth, ReviewDiffLayout.codeWidth(for: displayContent))
        lines.append(ReviewDiffRenderedLine(
            kind: kind,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            marker: marker,
            contentRange: contentRange,
            sourceContentUTF16Length: sourceContentUTF16Length,
            sourceFileURL: sourceFileURL,
            navigationSide: navigationSide,
            sourceLineNumber: sourceLineNumber,
            syntaxKey: syntaxKey,
            fallbackSyntaxKey: fallbackSyntaxKey
        ))
    }
}

private struct ReviewIndexedDiffLine: Equatable {
    let hunkIndex: Int
    let lineIndex: Int
    let line: SourceDiffLine
}

private struct ReviewDiffSideBySideRenderedRow: Equatable {
    let oldLine: ReviewIndexedDiffLine?
    let newLine: ReviewIndexedDiffLine?

    static func rows(hunkIndex: Int, lines: [SourceDiffLine]) -> [ReviewDiffSideBySideRenderedRow] {
        let indexedLines = lines.enumerated().map { lineIndex, line in
            ReviewIndexedDiffLine(hunkIndex: hunkIndex, lineIndex: lineIndex, line: line)
        }
        var rows: [ReviewDiffSideBySideRenderedRow] = []
        var index = 0

        while index < indexedLines.count {
            let indexedLine = indexedLines[index]
            let line = indexedLine.line

            if line.kind == .context {
                rows.append(ReviewDiffSideBySideRenderedRow(oldLine: indexedLine, newLine: indexedLine))
                index += 1
                continue
            }

            if line.kind == .deletion {
                var deletions: [ReviewIndexedDiffLine] = []
                while index < indexedLines.count, indexedLines[index].line.kind == .deletion {
                    deletions.append(indexedLines[index])
                    index += 1
                }

                var additions: [ReviewIndexedDiffLine] = []
                while index < indexedLines.count, indexedLines[index].line.kind == .addition {
                    additions.append(indexedLines[index])
                    index += 1
                }

                appendPairedRows(oldLines: deletions, newLines: additions, to: &rows)
                continue
            }

            var additions: [ReviewIndexedDiffLine] = []
            while index < indexedLines.count, indexedLines[index].line.kind == .addition {
                additions.append(indexedLines[index])
                index += 1
            }
            appendPairedRows(oldLines: [], newLines: additions, to: &rows)
        }

        return rows
    }

    private static func appendPairedRows(
        oldLines: [ReviewIndexedDiffLine],
        newLines: [ReviewIndexedDiffLine],
        to rows: inout [ReviewDiffSideBySideRenderedRow]
    ) {
        let rowCount = max(oldLines.count, newLines.count)
        for offset in 0..<rowCount {
            rows.append(ReviewDiffSideBySideRenderedRow(
                oldLine: line(at: offset, in: oldLines),
                newLine: line(at: offset, in: newLines)
            ))
        }
    }

    private static func line(at index: Int, in lines: [ReviewIndexedDiffLine]) -> ReviewIndexedDiffLine? {
        guard lines.indices.contains(index) else { return nil }
        return lines[index]
    }
}

private extension SourceDiffLine {
    var unifiedSyntaxSide: ReviewDiffSyntaxSide {
        kind == .deletion ? .old : .new
    }
}

private extension SourceDiffLine {
    var unifiedMarker: String {
        switch kind {
        case .context:
            " "
        case .addition:
            "+"
        case .deletion:
            "-"
        }
    }

    func marker(for side: ReviewDiffSyntaxSide) -> String {
        switch (kind, side) {
        case (.addition, .new):
            "+"
        case (.deletion, .old):
            "-"
        case (.context, _), (.addition, .old), (.deletion, .new):
            " "
        }
    }
}

enum ReviewDiffScrollLayout {
    static let minimumMeasurableViewportWidth: CGFloat = 80

    /// テキスト計測結果が依存する入力の署名。行高は固定のため、
    /// この署名が一致する限り再計測(ensureLayout)は不要。
    struct MeasurementSignature: Equatable {
        let textWidth: CGFloat
        let wrapLines: Bool
    }

    static func needsRemeasure(
        previous: MeasurementSignature?,
        candidate: MeasurementSignature,
        forced: Bool
    ) -> Bool {
        forced || previous != candidate
    }

    /// 行がビューポートの前後1画面分以内にあるか。NSScrollViewを持つペインは
    /// この範囲でのみ実体化し、範囲外は同一高さのプレースホルダに置き換える。
    /// viewportBounds が取れない場合は安全側(実体化)に倒す。
    static func isNearViewport(rowFrame: CGRect, viewportBounds: CGRect?) -> Bool {
        guard let viewportBounds else { return true }
        return rowFrame.intersects(
            viewportBounds.insetBy(dx: 0, dy: -viewportBounds.height)
        )
    }

    enum ScrollWheelRoute {
        case pane
        case parent
    }

    enum ScrollWheelEventPhase {
        case gestureBegan
        case gestureActive
        case momentum
        case discrete
    }

    static func canScrollHorizontally(
        documentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> Bool {
        documentWidth - viewportWidth > 0.5
    }

    static func scrollWheelRoute(
        phase: ScrollWheelEventPhase,
        deltaX: CGFloat,
        deltaY: CGFloat,
        canScrollHorizontally: Bool,
        activeRoute: ScrollWheelRoute?
    ) -> ScrollWheelRoute? {
        switch phase {
        case .gestureBegan:
            deltaRoute(deltaX: deltaX, deltaY: deltaY, canScrollHorizontally: canScrollHorizontally)
        case .gestureActive:
            activeRoute
                ?? deltaRoute(deltaX: deltaX, deltaY: deltaY, canScrollHorizontally: canScrollHorizontally)
        case .momentum:
            activeRoute ?? .parent
        case .discrete:
            deltaRoute(deltaX: deltaX, deltaY: deltaY, canScrollHorizontally: canScrollHorizontally)
                ?? .parent
        }
    }

    private static func deltaRoute(
        deltaX: CGFloat,
        deltaY: CGFloat,
        canScrollHorizontally: Bool
    ) -> ScrollWheelRoute? {
        guard deltaX != 0 || deltaY != 0 else { return nil }
        return canScrollHorizontally && abs(deltaX) > abs(deltaY) ? .pane : .parent
    }

    static func measurableViewportWidth(
        totalWidth: CGFloat,
        gutterWidth: CGFloat
    ) -> CGFloat? {
        let viewportWidth = totalWidth - gutterWidth
        guard viewportWidth >= minimumMeasurableViewportWidth else {
            return nil
        }
        return viewportWidth
    }

    static func textWidth(
        viewportWidth: CGFloat,
        documentCodeWidth: CGFloat,
        textInsetWidth: CGFloat,
        wrapLines: Bool
    ) -> CGFloat {
        guard !wrapLines else {
            return viewportWidth
        }

        return max(viewportWidth, documentCodeWidth + textInsetWidth * 2)
    }

    static func estimatedDocumentHeight(
        rowCount: Int,
        lineHeight: CGFloat,
        textInsetHeight: CGFloat
    ) -> CGFloat {
        max(lineHeight, CGFloat(max(1, rowCount)) * lineHeight + textInsetHeight * 2)
    }

    /// チャンク分割して積み上げた場合の合計推定高。各チャンクが上下 inset を
    /// 持つため単純な総行数×行高とは一致しない。プレースホルダは必ずこちらを
    /// 使い、チャンク側の推定高(estimatedRowCount 由来)と厳密に一致させること。
    static func estimatedChunkedDocumentHeight(
        chunkRowCounts: [Int],
        lineHeight: CGFloat,
        textInsetHeight: CGFloat
    ) -> CGFloat {
        chunkRowCounts.reduce(0) { height, rowCount in
            height + estimatedDocumentHeight(
                rowCount: rowCount,
                lineHeight: lineHeight,
                textInsetHeight: textInsetHeight
            )
        }
    }

    /// 折り返し時の推定表示行数。カラム数を1行あたりのカラム数で割り上げる。
    /// char-fit の下限推定のため word wrap の実測はこれ以上になり得る。
    /// チャンク予算側(maxEstimatedRowsPerWrappedPane)の安全係数で吸収する。
    static func estimatedWrappedRows(columns: Int, columnsPerRow: Int?) -> Int {
        guard let columnsPerRow, columnsPerRow > 0 else { return 1 }
        return max(1, (columns + columnsPerRow - 1) / columnsPerRow)
    }

    /// ペア行ごとの目標表示行数(old/new の実測折り返し行数の要素ごと max)。
    /// ドキュメント差し替え直後などで両サイドの行数が食い違う間は nil を返し、
    /// 呼び出し側は同期をスキップする(次の測定報告で再計算される)。
    static func pairedRowTargets(_ a: [Int], _ b: [Int]) -> [Int]? {
        guard a.count == b.count else { return nil }
        return zip(a, b).map(max)
    }

    /// 目標表示行数に対する不足行数。負にはならない。
    static func extraRows(natural: [Int], target: [Int]) -> [Int] {
        zip(natural, target).map { max(0, $1 - $0) }
    }

    /// 折り返し推定に使うペイン幅。ライブリサイズ中の再チャンクを抑えるため
    /// バケットに床丸めする(幅を小さめに見積もる=表示行を多めに見積もる=安全側)。
    static func bucketedPaneWidth(_ width: CGFloat, bucket: CGFloat = 64) -> CGFloat {
        max(bucket, floor(width / bucket) * bucket)
    }

    /// 1表示行に収まる推定カラム数(等幅前提)。
    static func estimatedColumnsPerRow(
        paneWidth: CGFloat,
        gutterWidth: CGFloat,
        textInsetWidth: CGFloat,
        characterWidth: CGFloat
    ) -> Int {
        guard characterWidth > 0 else { return 1 }
        let wrapWidth = paneWidth - gutterWidth - textInsetWidth * 2
        return max(8, Int(wrapWidth / characterWidth))
    }

    static func normalizedHorizontalOrigin(
        currentOrigin: CGFloat,
        documentWidth: CGFloat,
        viewportWidth: CGFloat,
        reset: Bool
    ) -> CGFloat {
        guard !reset else { return 0 }

        let maximumOrigin = max(0, documentWidth - viewportWidth)
        return min(max(0, currentOrigin), maximumOrigin)
    }
}

/// レビュー差分でファイルを最初から展開するかの方針。
/// 展開ペインはNSScrollViewを保持するため、極端な差分では上限を設けないと
/// ウィンドウ内のスクロールビュー蓄積でレイアウトが破綻する(GitHubの
/// "Large diffs are not rendered by default" と同じ発想)。
nonisolated enum ReviewDiffExpansionPolicy {
    static let largeDiffLineThreshold = 1500
    static let autoExpandFileLimit = 50

    static func initiallyExpanded(
        isViewed: Bool,
        lineCount: Int,
        fileIndex: Int
    ) -> Bool {
        !isViewed
            && lineCount <= largeDiffLineThreshold
            && fileIndex < autoExpandFileLimit
    }
}
