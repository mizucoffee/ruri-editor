//
//  CodePreviewPane.swift
//  ruri
//

import AppKit
import SwiftUI

struct CodePreviewPane: NSViewRepresentable {
    let document: CodePreviewDocument?
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> CodePreviewAppKitView {
        CodePreviewAppKitView()
    }

    func updateNSView(_ nsView: CodePreviewAppKitView, context: Context) {
        nsView.update(document: document, colorScheme: colorScheme)
    }
}

final class CodePreviewAppKitView: NSView {
    private struct PendingUpdate {
        let document: CodePreviewDocument
        let themeName: String
    }

    private static let codeFontSize: CGFloat = 12

    private let scrollView = NSScrollView()
    private let textView: NSTextView
    private let lineNumberRulerView: EditorLineNumberRulerView
    private var renderedRequest: CodePreviewRequest?
    private var renderedThemeName: String?
    private var renderedMatchRange: NSRange?
    private var pendingCenterRange: NSRange?
    private var pendingUpdate: PendingUpdate?

    init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        textView = CodePreviewTextView(frame: .zero, textContainer: textContainer)
        lineNumberRulerView = EditorLineNumberRulerView(scrollView: scrollView, textView: textView)
        super.init(frame: .zero)

        clipsToBounds = true
        configureTextView()
        configureScrollView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        scrollView.tile()
        lineNumberRulerView.invalidateLineNumbers()
        applyPendingUpdateIfReady()

        if let pendingCenterRange {
            self.pendingCenterRange = nil
            scrollToCenter(pendingCenterRange)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scrollView.tile()
        applyPendingUpdateIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingUpdateIfReady()
    }

    func update(document: CodePreviewDocument?, colorScheme: ColorScheme) {
        let themeName = SyntaxHighlightingService.themeName(
            for: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        )

        guard let document else {
            pendingUpdate = nil
            renderedRequest = nil
            renderedThemeName = themeName
            renderedMatchRange = nil
            pendingCenterRange = nil
            textView.textStorage?.setAttributedString(NSAttributedString())
            lineNumberRulerView.invalidateLineNumbers()
            return
        }

        guard isReadyForDisplay else {
            pendingUpdate = PendingUpdate(document: document, themeName: themeName)
            return
        }

        apply(document, themeName: themeName)
    }

    private var isReadyForDisplay: Bool {
        window != nil && bounds.height > 0 && bounds.width > 0
    }

    private func applyPendingUpdateIfReady() {
        guard let pendingUpdate, isReadyForDisplay else { return }

        self.pendingUpdate = nil
        apply(pendingUpdate.document, themeName: pendingUpdate.themeName)
    }

    private func apply(_ document: CodePreviewDocument, themeName: String) {
        guard document.request != renderedRequest || themeName != renderedThemeName else { return }

        let textLength = (document.text as NSString).length
        let matchRange = document.request.matchRange.nsRange.clamped(toUTF16Length: textLength)
        let canMoveHighlightOnly = renderedRequest?.url == document.request.url
            && renderedThemeName == themeName
            && textView.textStorage?.length == textLength

        if canMoveHighlightOnly {
            moveMatchHighlight(to: matchRange, themeName: themeName)
        } else {
            textView.textStorage?.setAttributedString(
                Self.attributedString(for: document, matchRange: matchRange, themeName: themeName)
            )
            lineNumberRulerView.invalidateLineNumbers()
        }

        renderedRequest = document.request
        renderedThemeName = themeName
        renderedMatchRange = matchRange

        scrollView.tile()
        scrollToCenter(matchRange)

        if matchRange.length > 0 {
            let request = document.request
            DispatchQueue.main.async { [weak self] in
                guard let self, self.renderedRequest == request else { return }
                self.textView.showFindIndicator(for: matchRange)
            }
        }
    }

    private func configureTextView() {
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesFindBar = false
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.font = NSFont.monospacedSystemFont(ofSize: Self.codeFontSize, weight: .regular)
    }

    private func configureScrollView() {
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.verticalRulerView = lineNumberRulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
    }

    private func moveMatchHighlight(to matchRange: NSRange, themeName: String) {
        guard let textStorage = textView.textStorage else { return }

        if let renderedMatchRange, renderedMatchRange.length > 0 {
            textStorage.removeAttribute(.backgroundColor, range: renderedMatchRange)
        }
        if matchRange.length > 0 {
            textStorage.addAttribute(
                .backgroundColor,
                value: Self.matchHighlightColor(themeName: themeName),
                range: matchRange
            )
        }
    }

    private func scrollToCenter(_ range: NSRange) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let visibleHeight = scrollView.contentView.bounds.height
        guard visibleHeight > 0 else {
            pendingCenterRange = range
            return
        }

        layoutManager.ensureLayout(for: textContainer)

        let string = textView.string as NSString
        let anchorLocation = min(range.location, string.length)
        let anchorRange = range.length > 0
            ? range
            : string.lineRange(for: NSRange(location: anchorLocation, length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: anchorRange, actualCharacterRange: nil)
        let matchRect = layoutManager
            .boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        let clipView = scrollView.contentView
        let proposedBounds = NSRect(
            origin: NSPoint(x: -1_000_000, y: matchRect.midY - visibleHeight / 2),
            size: clipView.bounds.size
        )
        let constrainedBounds = clipView.constrainBoundsRect(proposedBounds)

        clipView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private static func attributedString(
        for document: CodePreviewDocument,
        matchRange: NSRange,
        themeName: String
    ) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        let lineHeight = ceil(font.ascender - font.descender + font.leading) + 4
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * 4
        paragraphStyle.lineBreakMode = .byClipping

        let attributedString = NSMutableAttributedString(
            string: document.text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        for run in document.syntaxRuns {
            let range = run.range.clamped(toUTF16Length: attributedString.length)
            guard range.length > 0 else { continue }

            attributedString.addAttribute(
                .foregroundColor,
                value: SyntaxHighlightPalette.color(for: run.role, themeName: themeName),
                range: range
            )
        }

        if matchRange.length > 0 {
            attributedString.addAttribute(
                .backgroundColor,
                value: matchHighlightColor(themeName: themeName),
                range: matchRange
            )
        }

        return attributedString
    }

    private static func matchHighlightColor(themeName: String) -> NSColor {
        let isDark = themeName.contains("dark")
        return NSColor.systemYellow.withAlphaComponent(isDark ? 0.30 : 0.36)
    }
}

private final class CodePreviewTextView: NSTextView {
    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    ) -> NSRange {
        let fallback = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        guard granularity == .selectByWord else { return fallback }

        return EditorWordSelection.wordSelectionRange(
            in: string as NSString,
            proposedRange: proposedCharRange,
            fallback: fallback
        )
    }
}
