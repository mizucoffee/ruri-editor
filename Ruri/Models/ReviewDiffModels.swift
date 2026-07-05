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
        maximumCodeWidth: ReviewDiffLayout.codeWidth(for: " ")
    )

    let pane: Pane
    let text: String
    let lines: [ReviewDiffRenderedLine]
    let maximumCodeWidth: CGFloat

    var lineCount: Int {
        lines.count
    }

    /// 実ドキュメントを構築せずに描画行数だけを返す(オフスクリーン行の
    /// プレースホルダ高の算出用)。行高は固定のため行数×行高が正確な高さになる。
    /// `unified(file:oldFileURL:newFileURL:)` の行生成(hunkヘッダ1行 + 各行)と
    /// 厳密に一致させること。
    static func unifiedLineCount(for file: GitReviewFileDiff) -> Int {
        file.diff.hunks.reduce(0) { $0 + 1 + $1.lines.count }
    }

    /// `sideBySide(file:side:fileURL:)` と厳密に一致する行数。ペア化により
    /// old/new 両ペインの行数は常に等しい。
    static func sideBySideLineCount(for file: GitReviewFileDiff) -> Int {
        file.diff.hunks.reduce(0) { count, hunk in
            count + 1 + ReviewDiffSideBySideRenderedRow.rows(hunkIndex: 0, lines: hunk.lines).count
        }
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
            maxLinesPerDocument: Int.max
        )[0]
    }

    /// 長いファイルを maxLinesPerDocument 行ごとの複数ドキュメントに分割して返す。
    /// レイヤーバックの巨大ビューはRetinaで約8,000pt(テクスチャ上限16384px)を
    /// 超えた部分の描画が破棄されるため、ペインは分割して積み上げる必要がある。
    /// 分割は「N行追加するごと」の機械的な境界で、side-by-side の old/new とも
    /// 追加順序が同一のため境界は必ず一致する。
    static func unifiedDocuments(
        for file: GitReviewFileDiff,
        oldFileURL: URL?,
        newFileURL: URL?,
        maxLinesPerDocument: Int
    ) -> [ReviewDiffRenderedDocument] {
        var chunker = ReviewDiffRenderedDocumentChunker(
            pane: .unified,
            maxLinesPerDocument: maxLinesPerDocument
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
            maxLinesPerDocument: Int.max
        )[0]
    }

    /// `unifiedDocuments(for:...)` の side-by-side 版。old/new は行のペア化により
    /// 追加順序・行数が完全に一致するため、同じ maxLinesPerDocument なら
    /// 両サイドのチャンク境界と各チャンクの行数も一致する。
    static func sideBySideDocuments(
        for file: GitReviewFileDiff,
        side: ReviewDiffSyntaxSide,
        fileURL: URL?,
        maxLinesPerDocument: Int
    ) -> [ReviewDiffRenderedDocument] {
        var chunker = ReviewDiffRenderedDocumentChunker(
            pane: side == .old ? .old : .new,
            maxLinesPerDocument: maxLinesPerDocument
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

/// maxLinesPerDocument 行を超えるたびにビルダーを切り替え、複数ドキュメントを生成する。
private struct ReviewDiffRenderedDocumentChunker {
    private let pane: ReviewDiffRenderedDocument.Pane
    private let maxLinesPerDocument: Int
    private var builder: ReviewDiffRenderedDocumentBuilder
    private var documents: [ReviewDiffRenderedDocument] = []
    private var lineCount = 0

    init(pane: ReviewDiffRenderedDocument.Pane, maxLinesPerDocument: Int) {
        self.pane = pane
        self.maxLinesPerDocument = max(1, maxLinesPerDocument)
        self.builder = ReviewDiffRenderedDocumentBuilder(pane: pane)
    }

    mutating func withBuilder(_ append: (inout ReviewDiffRenderedDocumentBuilder) -> Void) {
        if lineCount == maxLinesPerDocument {
            documents.append(builder.build())
            builder = ReviewDiffRenderedDocumentBuilder(pane: pane)
            lineCount = 0
        }
        append(&builder)
        lineCount += 1
    }

    mutating func finish() -> [ReviewDiffRenderedDocument] {
        if lineCount > 0 || documents.isEmpty {
            documents.append(builder.build())
        }
        return documents
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

    mutating func build() -> ReviewDiffRenderedDocument {
        if lines.isEmpty {
            appendPlaceholder()
        }

        return ReviewDiffRenderedDocument(
            pane: pane,
            text: text,
            lines: lines,
            maximumCodeWidth: maximumCodeWidth
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

        let displayContent = content.isEmpty ? " " : content
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
        lineCount: Int,
        lineHeight: CGFloat,
        textInsetHeight: CGFloat
    ) -> CGFloat {
        max(lineHeight, CGFloat(max(1, lineCount)) * lineHeight + textInsetHeight * 2)
    }

    /// チャンク分割して積み上げた場合の合計高。各チャンクが上下 inset を持つため、
    /// 単一ドキュメントの推定高とはチャンク数に応じて差が出る。プレースホルダは
    /// 必ずこちらを使い、実体化後の高さと厳密に一致させること。
    static func estimatedChunkedDocumentHeight(
        totalLineCount: Int,
        maxLinesPerDocument: Int,
        lineHeight: CGFloat,
        textInsetHeight: CGFloat
    ) -> CGFloat {
        let clampedMax = max(1, maxLinesPerDocument)
        let lineCount = max(1, totalLineCount)
        let fullChunks = lineCount / clampedMax
        let remainder = lineCount % clampedMax

        var height = CGFloat(fullChunks) * estimatedDocumentHeight(
            lineCount: clampedMax,
            lineHeight: lineHeight,
            textInsetHeight: textInsetHeight
        )
        if remainder > 0 {
            height += estimatedDocumentHeight(
                lineCount: remainder,
                lineHeight: lineHeight,
                textInsetHeight: textInsetHeight
            )
        }
        return height
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
