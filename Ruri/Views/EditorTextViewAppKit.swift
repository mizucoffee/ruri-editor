//
//  EditorTextViewAppKit.swift
//  ruri
//

import AppKit

final class RuntimeTextView: NSTextView {
    weak var runtime: EditorDocumentRuntime?
    var indentGuideConfiguration = EditorIndentGuideConfiguration.disabled {
        didSet {
            guard oldValue != indentGuideConfiguration else { return }

            needsDisplay = true
        }
    }

    private var implementationHoverTrackingArea: NSTrackingArea?

    override var undoManager: UndoManager? {
        runtime?.textUndoManager
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawSelectedLineHighlights(in: dirtyRect)
        drawIndentGuides(in: dirtyRect)
        drawFindHighlights(in: dirtyRect)
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        runtime?.breakUndoCoalescing()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            runtime?.breakUndoCoalescing()
            runtime?.clearImplementationHover()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let implementationHoverTrackingArea {
            removeTrackingArea(implementationHoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        implementationHoverTrackingArea = trackingArea
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           runtime?.requestImplementationJump(at: event) == true {
            return
        }

        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        runtime?.updateImplementationHover(at: event)
    }

    override func mouseExited(with event: NSEvent) {
        runtime?.clearImplementationHover()
        super.mouseExited(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        runtime?.updateImplementationHoverForCurrentMouseLocation(modifierFlags: event.modifierFlags)
    }

    override func keyDown(with event: NSEvent) {
        if Self.isDeleteLineEvent(event),
           runtime?.deleteCurrentLinesWhenSelectionIsEmpty() == true {
            return
        }

        super.keyDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addImplementationHoverCursorRects()
    }

    override func insertTab(_ sender: Any?) {
        if runtime?.insertTab() == true {
            return
        }

        super.insertTab(sender)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            menuItem.title = runtime?.undoCommandTitle ?? "Undo"
            return runtime?.undoCommandState.canUndo ?? false

        case #selector(redo(_:)):
            menuItem.title = runtime?.redoCommandTitle ?? "Redo"
            return runtime?.undoCommandState.canRedo ?? false

        case #selector(copy(_:)):
            if runtime?.canCopyCurrentLinesWhenSelectionIsEmpty == true {
                return true
            }

            return super.validateMenuItem(menuItem)

        case #selector(cut(_:)):
            if runtime?.canCutCurrentLinesWhenSelectionIsEmpty == true {
                return true
            }

            return super.validateMenuItem(menuItem)

        default:
            return super.validateMenuItem(menuItem)
        }
    }

    override func performFindPanelAction(_ sender: Any?) {
        runtime?.presentFind(showsReplace: false)
    }

    override func copy(_ sender: Any?) {
        if runtime?.copyCurrentLinesWhenSelectionIsEmpty() == true {
            return
        }

        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        if runtime?.cutCurrentLinesWhenSelectionIsEmpty() == true {
            return
        }

        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        if runtime?.pasteLineClipboardAboveCurrentLineWhenSelectionIsEmpty() == true {
            return
        }

        super.paste(sender)
    }

    @objc func undo(_ sender: Any?) {
        runtime?.performUndo()
    }

    @objc func redo(_ sender: Any?) {
        runtime?.performRedo()
    }

    private static func isDeleteLineEvent(_ event: NSEvent) -> Bool {
        guard event.charactersIgnoringModifiers == "\u{7F}" else {
            return false
        }

        let editingModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return editingModifiers == .command
    }

    private func addImplementationHoverCursorRects() {
        guard runtime?.implementationHoverRange != nil else {
            return
        }

        addCursorRect(bounds, cursor: .pointingHand)

        guard let hoverRange = runtime?.implementationHoverRange,
              hoverRange.length > 0,
              let layoutManager,
              let textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: hoverRange,
            actualCharacterRange: nil
        )
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            let cursorRect = rect
                .offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                .insetBy(dx: -1, dy: -1)
            self.addCursorRect(cursorRect, cursor: .pointingHand)
        }
    }

    fileprivate var selectedLineRanges: [NSRange] {
        EditorDocumentRuntime.selectedLineRanges(
            in: string,
            selectedRanges: selectedRanges.map(\.rangeValue)
        )
    }

    private func drawSelectedLineHighlights(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer else {
            return
        }

        let lineRanges = selectedLineRanges
        guard !lineRanges.isEmpty else { return }

        layoutManager.ensureLayout(for: textContainer)
        EditorLineHighlightStyle.fillColor(for: effectiveAppearance).setFill()

        for lineRange in lineRanges {
            drawSelectedLineHighlight(
                for: lineRange,
                dirtyRect: dirtyRect,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }
    }

    private func drawSelectedLineHighlight(
        for lineRange: NSRange,
        dirtyRect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        if lineRange.length == 0 {
            drawEmptyLineHighlight(dirtyRect: dirtyRect, layoutManager: layoutManager)
            return
        }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: lineRange,
            actualCharacterRange: nil
        )
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            let highlightRect = self.selectedLineHighlightRect(for: lineRect)
            if highlightRect.intersects(dirtyRect) {
                highlightRect.fill()
            }
        }
    }

    private func drawEmptyLineHighlight(dirtyRect: NSRect, layoutManager: NSLayoutManager) {
        let lineRect: NSRect
        if !layoutManager.extraLineFragmentRect.isEmpty {
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            lineRect = NSRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: font?.defaultLineHeight(for: self) ?? 0
            )
        }

        let highlightRect = selectedLineHighlightRect(for: lineRect)
        if highlightRect.intersects(dirtyRect) {
            highlightRect.fill()
        }
    }

    private func selectedLineHighlightRect(for lineRect: NSRect) -> NSRect {
        NSRect(
            x: 0,
            y: lineRect.minY + textContainerOrigin.y,
            width: bounds.width,
            height: max(1, lineRect.height)
        )
    }

    private func drawIndentGuides(in dirtyRect: NSRect) {
        guard indentGuideConfiguration.isEnabled,
              let layoutManager,
              let textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let string = self.string as NSString
        guard string.length > 0,
              layoutManager.numberOfGlyphs > 0 else {
            return
        }

        let visibleContainerRect = NSRect(
            x: dirtyRect.minX - textContainerOrigin.x,
            y: dirtyRect.minY - textContainerOrigin.y,
            width: dirtyRect.width,
            height: dirtyRect.height
        )
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let initialLocation = min(characterRange.location, string.length)
        let initialLineRange = string.lineRange(for: NSRange(location: initialLocation, length: 0))
        var lineStart = initialLineRange.location

        EditorIndentGuideStyle.strokeColor(for: effectiveAppearance).setFill()

        while lineStart < string.length {
            let lineRange = string.lineRange(for: NSRange(location: lineStart, length: 0))
            let guideCount = EditorIndentGuideCalculator.guideCount(
                in: string,
                lineRange: lineRange,
                tabWidth: indentGuideConfiguration.tabWidth
            )

            if guideCount > 0 {
                drawIndentGuides(
                    guideCount: guideCount,
                    lineRange: lineRange,
                    dirtyRect: dirtyRect,
                    layoutManager: layoutManager,
                    textContainer: textContainer
                )
            }

            let nextLineStart = NSMaxRange(lineRange)
            guard nextLineStart > lineStart else { break }

            lineStart = nextLineStart
        }
    }

    private func drawIndentGuides(
        guideCount: Int,
        lineRange: NSRange,
        dirtyRect: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: lineRange,
            actualCharacterRange: nil
        )
        guard glyphRange.location != NSNotFound,
              glyphRange.length > 0 else {
            return
        }

        let scale = backingScaleFactor
        let lineWidth = 1 / scale
        let textOrigin = textContainerOrigin

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
            for level in 1...guideCount {
                let rawX = textOrigin.x +
                    lineRect.minX +
                    textContainer.lineFragmentPadding +
                    CGFloat(level) * self.indentGuideConfiguration.levelWidth
                let x = (rawX * scale).rounded(.down) / scale
                let guideRect = NSRect(
                    x: x,
                    y: lineRect.minY + textOrigin.y + 1,
                    width: lineWidth,
                    height: max(1, lineRect.height - 2)
                )

                if guideRect.intersects(dirtyRect) {
                    guideRect.fill()
                }
            }
        }
    }

    private func drawFindHighlights(in dirtyRect: NSRect) {
        guard let findState = runtime?.findState,
              findState.isPresented,
              !findState.matches.isEmpty,
              let layoutManager,
              let textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        for (index, range) in findState.matches.enumerated() where range.length > 0 {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let fillColor = EditorFindHighlightStyle.fillColor(
                isSelected: index == findState.selectedMatchIndex,
                appearance: effectiveAppearance
            )
            fillColor.setFill()

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                let highlightRect = rect
                    .offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                    .insetBy(dx: -1.5, dy: -1)
                if highlightRect.intersects(dirtyRect) {
                    NSBezierPath(roundedRect: highlightRect, xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }

    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

}

struct EditorIndentGuideConfiguration: Equatable {
    static let disabled = EditorIndentGuideConfiguration(tabWidth: 0, levelWidth: 0)

    let tabWidth: Int
    let levelWidth: CGFloat

    var isEnabled: Bool {
        tabWidth > 0 && levelWidth > 0
    }
}

enum EditorIndentGuideCalculator {
    static func guideCount(
        in string: NSString,
        lineRange: NSRange,
        tabWidth: Int
    ) -> Int {
        guard tabWidth > 0,
              string.length > 0,
              lineRange.location >= 0,
              lineRange.location < string.length else {
            return 0
        }

        let lineEnd = min(NSMaxRange(lineRange), string.length)
        var index = lineRange.location
        var visualColumn = 0

        while index < lineEnd {
            switch string.character(at: index) {
            case 9:
                let remainder = visualColumn % tabWidth
                visualColumn += remainder == 0 ? tabWidth : tabWidth - remainder
            case 32:
                visualColumn += 1
            case 10, 13:
                return visualColumn / tabWidth
            default:
                return max(0, visualColumn - 1) / tabWidth
            }

            index += 1
        }

        return visualColumn / tabWidth
    }
}

private enum EditorLineHighlightStyle {
    static func fillColor(for appearance: NSAppearance) -> NSColor {
        let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? 0.16
            : 0.10
        return NSColor.controlAccentColor.withAlphaComponent(alpha)
    }
}

private enum EditorFindHighlightStyle {
    static func fillColor(isSelected: Bool, appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isSelected {
            return NSColor.systemOrange.withAlphaComponent(isDark ? 0.42 : 0.32)
        }

        return NSColor.systemYellow.withAlphaComponent(isDark ? 0.30 : 0.36)
    }
}

private enum EditorIndentGuideStyle {
    static func strokeColor(for appearance: NSAppearance) -> NSColor {
        let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? 0.22
            : 0.16
        return NSColor.separatorColor.withAlphaComponent(alpha)
    }
}

final class EditorLineNumberRulerView: NSRulerView {
    private static let minimumThickness: CGFloat = 36
    private static let horizontalPadding: CGFloat = 7
    private static let separatorThickness: CGFloat = 1

    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)

        clientView = textView
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        ruleThickness = Self.minimumThickness
        invalidateLineNumbers()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func invalidateLineNumbers() {
        let newThickness = calculatedRuleThickness
        if abs(ruleThickness - newThickness) > .ulpOfOne {
            ruleThickness = newThickness
            scrollView?.tile()
        }

        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        drawBackground()

        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let string = textView.string as NSString
        let visibleTextRect = textView.visibleRect
        let visibleContainerRect = NSRect(
            x: visibleTextRect.minX - textView.textContainerOrigin.x,
            y: visibleTextRect.minY - textView.textContainerOrigin.y,
            width: visibleTextRect.width,
            height: visibleTextRect.height
        )
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let initialLocation = min(characterRange.location, string.length)
        let initialLineRange = string.lineRange(for: NSRange(location: initialLocation, length: 0))
        var lineStart = initialLineRange.location
        var lineNumber = Self.lineNumber(atCharacterIndex: lineStart, in: string)
        let relativePoint = convert(NSPoint.zero, from: textView)
        let selectedLineStarts = Set((textView as? RuntimeTextView)?
            .selectedLineRanges
            .map(\.location) ?? [])
        let diffDecorationsByLine = Dictionary(
            grouping: (textView as? RuntimeTextView)?.runtime?.diffDecorations ?? [],
            by: \.lineNumber
        )

        while lineStart <= string.length {
            let lineRange = string.lineRange(for: NSRange(location: lineStart, length: 0))
            if let lineRect = lineFragmentRect(
                forLineStart: lineStart,
                textView: textView,
                layoutManager: layoutManager,
                string: string
            ) {
                let y = lineRect.minY + textView.textContainerOrigin.y + relativePoint.y
                if y > visibleTextRect.maxY + relativePoint.y {
                    break
                }

                let isSelectedLine = selectedLineStarts.contains(lineRange.location)
                if isSelectedLine {
                    drawSelectedLineBackground(y: y, height: lineRect.height)
                }

                if let diffDecorations = diffDecorationsByLine[lineNumber] {
                    drawDiffMarkers(diffDecorations, y: y, height: lineRect.height)
                }

                drawLineNumber(
                    lineNumber,
                    y: y,
                    height: lineRect.height,
                    attributes: lineNumberAttributes(for: textView, isSelectedLine: isSelectedLine)
                )
            }

            let nextLineStart = NSMaxRange(lineRange)
            if nextLineStart >= string.length {
                guard nextLineStart == string.length,
                      string.endsWithLineSeparator,
                      lineStart != string.length else {
                    break
                }

                lineStart = nextLineStart
            } else {
                lineStart = nextLineStart
            }

            lineNumber += 1
        }
    }

    private var calculatedRuleThickness: CGFloat {
        guard let textView = clientView as? NSTextView else {
            return Self.minimumThickness
        }

        let digitCount = max(1, String(Self.lineCount(in: textView.string as NSString)).count)
        let sample = String(repeating: "8", count: digitCount) as NSString
        let width = ceil(max(
            sample.size(withAttributes: lineNumberAttributes(for: textView, isSelectedLine: false)).width,
            sample.size(withAttributes: lineNumberAttributes(for: textView, isSelectedLine: true)).width
        ))

        return max(Self.minimumThickness, width + Self.horizontalPadding * 2)
    }

    private func drawBackground() {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        let separatorWidth = Self.separatorThickness / backingScaleFactor
        NSRect(
            x: bounds.maxX - separatorWidth,
            y: bounds.minY,
            width: separatorWidth,
            height: bounds.height
        ).fill()
    }

    private func drawSelectedLineBackground(y: CGFloat, height: CGFloat) {
        EditorLineHighlightStyle.fillColor(for: effectiveAppearance).setFill()
        NSRect(
            x: bounds.minX,
            y: y,
            width: bounds.width,
            height: max(1, height)
        ).fill()
    }

    private func drawDiffMarkers(
        _ decorations: [EditorDiffDecoration],
        y: CGFloat,
        height: CGFloat
    ) {
        for kind in orderedDiffKinds(in: decorations) {
            EditorDiffMarkerStyle.color(for: kind, appearance: effectiveAppearance).setFill()

            switch kind {
            case .added, .modified:
                NSRect(
                    x: bounds.minX + 1,
                    y: y + 1,
                    width: 3,
                    height: max(1, height - 2)
                ).fill()

            case .deleted:
                NSRect(
                    x: bounds.minX + 1,
                    y: max(bounds.minY, y - 1),
                    width: 10,
                    height: 2
                ).fill()
            }
        }
    }

    private func orderedDiffKinds(in decorations: [EditorDiffDecoration]) -> [EditorDiffDecoration.Kind] {
        [.deleted, .modified, .added].filter { kind in
            decorations.contains { $0.kind == kind }
        }
    }

    private var backingScaleFactor: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }

    private func drawLineNumber(
        _ lineNumber: Int,
        y: CGFloat,
        height: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let string = "\(lineNumber)" as NSString
        let size = string.size(withAttributes: attributes)
        let drawRect = NSRect(
            x: max(0, bounds.width - Self.horizontalPadding - size.width),
            y: y + max(0, (height - size.height) / 2),
            width: size.width,
            height: size.height
        )

        string.draw(in: drawRect, withAttributes: attributes)
    }

    private func lineFragmentRect(
        forLineStart lineStart: Int,
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        string: NSString
    ) -> NSRect? {
        if lineStart == string.length {
            let extraLineFragmentRect = layoutManager.extraLineFragmentRect
            if !extraLineFragmentRect.isEmpty {
                return extraLineFragmentRect
            }

            return NSRect(
                x: 0,
                y: 0,
                width: textView.bounds.width,
                height: textView.font?.defaultLineHeight(for: textView) ?? 0
            )
        }

        guard lineStart >= 0,
              lineStart < string.length,
              layoutManager.numberOfGlyphs > 0 else {
            return nil
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: lineStart)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        return layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
    }

    private func lineNumberAttributes(
        for textView: NSTextView,
        isSelectedLine: Bool
    ) -> [NSAttributedString.Key: Any] {
        let pointSize = max(10, (textView.font?.pointSize ?? NSFont.systemFontSize) - 1)
        return [
            .font: NSFont.monospacedSystemFont(
                ofSize: pointSize,
                weight: isSelectedLine ? .semibold : .regular
            ),
            .foregroundColor: isSelectedLine ? NSColor.labelColor : NSColor.secondaryLabelColor
        ]
    }

    private static func lineCount(in string: NSString) -> Int {
        guard string.length > 0 else { return 1 }

        var lineCount = 1
        var searchRange = NSRange(location: 0, length: string.length)

        while searchRange.length > 0 {
            let range = string.range(of: "\n", options: [], range: searchRange)
            guard range.location != NSNotFound else { break }

            lineCount += 1
            let nextLocation = NSMaxRange(range)
            searchRange = NSRange(
                location: nextLocation,
                length: string.length - nextLocation
            )
        }

        return lineCount
    }

    private static func lineNumber(atCharacterIndex characterIndex: Int, in string: NSString) -> Int {
        guard characterIndex > 0,
              string.length > 0 else {
            return 1
        }

        let cappedLocation = min(characterIndex, string.length)
        var lineNumber = 1
        var searchRange = NSRange(location: 0, length: cappedLocation)

        while searchRange.length > 0 {
            let range = string.range(of: "\n", options: [], range: searchRange)
            guard range.location != NSNotFound else { break }

            lineNumber += 1
            let nextLocation = NSMaxRange(range)
            searchRange = NSRange(
                location: nextLocation,
                length: cappedLocation - nextLocation
            )
        }

        return lineNumber
    }
}

private enum EditorDiffMarkerStyle {
    static func color(
        for kind: EditorDiffDecoration.Kind,
        appearance: NSAppearance
    ) -> NSColor {
        switch kind {
        case .added:
            return .systemGreen
        case .modified:
            return .systemOrange
        case .deleted:
            return .systemRed
        }
    }
}

private extension NSString {
    var endsWithLineSeparator: Bool {
        guard length > 0 else { return false }

        return character(at: length - 1) == 10
    }
}

private extension NSFont {
    func defaultLineHeight(for textView: NSTextView) -> CGFloat {
        let fallbackHeight = ceil(ascender - descender + leading)
        return max(fallbackHeight, textView.layoutManager?.defaultLineHeight(for: self) ?? fallbackHeight)
    }
}
