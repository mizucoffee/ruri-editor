//
//  EditorDocumentRuntime.swift
//  ruri
//

import AppKit
import Foundation

@MainActor
final class EditorDocumentRuntime: NSObject, NSTextViewDelegate {
    let workspaceID: ProjectWorkspaceSnapshot.ID
    let documentID: OpenDocument.ID
    let scrollView: NSScrollView

    weak var delegate: EditorDocumentRuntimeDelegate?

    let textUndoManager = UndoManager()

    private let session: EditorDocumentSession
    private let syntaxHighlightingService: SyntaxHighlightingService
    private let inferredSyntaxLanguageName: String?
    private let editorFont = NSFont.monospacedSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )
    private let editorLineHeightMultiple: CGFloat = 1.2
    private let textView: RuntimeTextView
    private let diffScroller: EditorDiffScroller
    private var lineNumberRulerView: EditorLineNumberRulerView? {
        scrollView.verticalRulerView as? EditorLineNumberRulerView
    }
    private weak var observedClipView: NSClipView?
    private var isApplyingProgrammaticChange = false
    private var isApplyingSyntaxAttributes = false
    private var isRestoringSelection = false
    private var isRestoringScroll = false
    private var undoCoalescingBreakTask: Task<Void, Never>?
    private var syntaxHighlightTask: Task<Void, Never>?
    private var syntaxHighlightGeneration = 0
    private var lastSyntaxHighlightedText: String?
    private var lastSyntaxHighlightedThemeName: String?
    private var lastSyntaxHighlightedLanguageName: String?
    private var tabInputSetting = EditorTabInputSetting.defaultValue
    private var lineWrappingMode = EditorLineWrappingMode.defaultValue
    private var isSyntaxHighlightingDisabledForLargeDocument = false
    private var appliedSelectionRevealID: UUID?
    private var mutableFindState = EditorFindState()
    private(set) var diffDecorations: [EditorDiffDecoration] = []
    private var implementationHoverTask: Task<Void, Never>?
    private var implementationHoverRequestID = UUID()
    private var implementationHoverQueryRange: TextRange?
    private var implementationHoverHitCache: [TextRange: TextRange] = [:]
    private var implementationHoverMissCache = Set<TextRange>()
    private var activeImplementationHoverRange: NSRange?

    init(
        workspaceID: ProjectWorkspaceSnapshot.ID,
        documentID: OpenDocument.ID,
        initialText: String,
        session: EditorDocumentSession,
        syntaxHighlightingService: SyntaxHighlightingService
    ) {
        self.workspaceID = workspaceID
        self.documentID = documentID
        self.session = session
        self.syntaxHighlightingService = syntaxHighlightingService
        inferredSyntaxLanguageName = SyntaxLanguageResolver.languageName(for: documentID)

        let editorViews = Self.makeEditorViews()
        scrollView = editorViews.scrollView
        textView = editorViews.textView
        diffScroller = editorViews.diffScroller

        super.init()

        configure(scrollView: scrollView, textView: textView)
        configure(diffScroller: diffScroller)
        setText(initialText, registeringUndo: false)
        requestSyntaxHighlighting()
        restoreSelection()
        observeBoundsChanges(in: scrollView.contentView)
    }

    func prepareForHide() {
        breakUndoCoalescing()
        clearImplementationHover()
        session.selectedRange = textView.selectedRange()
        session.scrollOrigin = scrollView.contentView.bounds.origin
    }

    var isTextViewFirstResponder: Bool {
        textView.window?.firstResponder === textView
    }

    func activate(focusesTextView: Bool) {
        refreshSyntaxHighlightingIfNeeded()
        restoreSelection()
        restoreScroll()

        guard focusesTextView else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.textView.window?.firstResponder !== self.textView else {
                return
            }

            self.textView.window?.makeFirstResponder(self.textView)
        }
    }

    func invalidate() {
        undoCoalescingBreakTask?.cancel()
        undoCoalescingBreakTask = nil
        syntaxHighlightTask?.cancel()
        syntaxHighlightTask = nil
        clearImplementationHover()

        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView
            )
        }

        observedClipView = nil
        textView.delegate = nil
        textView.runtime = nil
    }

    func syncExternalTextIfNeeded(_ text: String) {
        guard textView.string != text,
              textView.window?.firstResponder !== textView,
              !textView.hasMarkedText() else {
            return
        }

        setText(text, registeringUndo: false)
        requestSyntaxHighlighting()
        restoreSelection()
        refreshFindMatches(preservingSelectedRange: true)
    }

    func applyPendingSelectionRevealIfNeeded() {
        guard let selectionRevealID = session.pendingSelectionRevealID,
              appliedSelectionRevealID != selectionRevealID else {
            return
        }

        appliedSelectionRevealID = selectionRevealID
        session.pendingSelectionRevealID = nil
        restoreSelection()
        scrollSelectionToVisible()
    }

    func updateLayout() {
        let contentSize = scrollView.contentSize
        let isWrappingEnabled = lineWrappingMode.isWrappingEnabled
        let rulerThickness = lineNumberRulerView?.requiredThickness ?? 0
        let wrappedTextWidth = max(0, contentSize.width - rulerThickness)
        let textContainerWidth = isWrappingEnabled ? wrappedTextWidth : CGFloat.greatestFiniteMagnitude
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !isWrappingEnabled
        textView.autoresizingMask = isWrappingEnabled ? [.width] : []
        scrollView.hasHorizontalScroller = !isWrappingEnabled
        textView.textContainer?.containerSize = NSSize(
            width: textContainerWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = isWrappingEnabled
        if isWrappingEnabled {
            var textFrame = textView.frame
            textFrame.size.width = wrappedTextWidth
            textView.frame = textFrame
        }
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
        scrollView.tile()
        textView.window?.invalidateCursorRects(for: textView)
        lineNumberRulerView?.invalidateLineNumbers()
        diffScroller.needsDisplay = true
    }

    func updateDiffDecorations(_ decorations: [EditorDiffDecoration]) {
        guard diffDecorations != decorations else { return }

        diffDecorations = decorations
        diffScroller.diffDecorations = decorations
        textView.needsDisplay = true
        lineNumberRulerView?.needsDisplay = true
        diffScroller.needsDisplay = true
    }

    func breakUndoCoalescing() {
        undoCoalescingBreakTask?.cancel()
        undoCoalescingBreakTask = nil

        guard !textView.hasMarkedText() else { return }
        textView.breakUndoCoalescing()
    }

    var undoCommandState: EditorUndoCommandState {
        EditorUndoCommandState(
            canUndo: textUndoManager.canUndo,
            canRedo: textUndoManager.canRedo,
            undoActionName: textUndoManager.undoActionName,
            redoActionName: textUndoManager.redoActionName
        )
    }

    var undoCommandTitle: String {
        Self.commandTitle(base: "Undo", actionName: textUndoManager.undoActionName)
    }

    var redoCommandTitle: String {
        Self.commandTitle(base: "Redo", actionName: textUndoManager.redoActionName)
    }

    var cursorPosition: EditorCursorPosition {
        Self.cursorPosition(in: textView.string, selectedRange: textView.selectedRange())
    }

    var syntaxLanguageState: EditorSyntaxLanguageState {
        EditorSyntaxLanguageState(
            inferredLanguageName: inferredSyntaxLanguageName,
            overrideLanguageName: session.syntaxLanguageOverride,
            languageOptions: syntaxHighlightingService.supportedLanguageOptions
        )
    }

    func updateTabInputSetting(_ setting: EditorTabInputSetting) {
        guard tabInputSetting != setting else { return }

        tabInputSetting = setting
        applyTabInputAttributes()
        applyIndentGuideConfiguration()
    }

    func updateLineWrappingMode(_ mode: EditorLineWrappingMode) {
        guard lineWrappingMode != mode else { return }

        lineWrappingMode = mode
        session.selectedRange = textView.selectedRange()
        session.scrollOrigin = scrollView.contentView.bounds.origin
        updateLayout()
        restoreScroll()
        textView.needsDisplay = true
    }

    @discardableResult
    func insertTab() -> Bool {
        guard !textView.hasMarkedText() else { return false }

        breakUndoCoalescing()

        let selectedRange = textView.selectedRange().clamped(toUTF16Length: textView.string.utf16.count)
        if selectedRange.length > 0,
           selectedLineRangesForIndenting(selectedRange).count > 1 {
            indentSelectedLines(in: selectedRange)
        } else {
            let replacement = tabReplacement(at: selectedRange.location)
            textView.insertText(replacement, replacementRange: selectedRange)
        }

        breakUndoCoalescing()
        return true
    }

    @discardableResult
    func deleteCurrentLinesWhenSelectionIsEmpty() -> Bool {
        guard !textView.hasMarkedText(),
              let deletionRange = selectedLineDeletionRange() else {
            return false
        }

        breakUndoCoalescing()
        textView.insertText("", replacementRange: deletionRange)
        breakUndoCoalescing()
        return true
    }

    @discardableResult
    func copyCurrentLinesWhenSelectionIsEmpty() -> Bool {
        guard !textView.hasMarkedText(),
              let lineText = selectedLineClipboardTextForEmptySelection() else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(lineText, forType: .string)
    }

    @discardableResult
    func cutCurrentLinesWhenSelectionIsEmpty() -> Bool {
        guard !textView.hasMarkedText(),
              let lineText = selectedLineClipboardTextForEmptySelection(),
              let deletionRange = selectedLineDeletionRange() else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(lineText, forType: .string) else {
            return false
        }

        breakUndoCoalescing()
        textView.insertText("", replacementRange: deletionRange)
        breakUndoCoalescing()
        return true
    }

    @discardableResult
    func pasteLineClipboardAboveCurrentLineWhenSelectionIsEmpty() -> Bool {
        guard !textView.hasMarkedText(),
              let lineText = NSPasteboard.general.string(forType: .string),
              Self.isLineClipboardText(lineText),
              let insertionRange = linePasteInsertionRange() else {
            return false
        }

        breakUndoCoalescing()
        textView.insertText(lineText, replacementRange: insertionRange)
        breakUndoCoalescing()
        return true
    }

    var canCopyCurrentLinesWhenSelectionIsEmpty: Bool {
        !textView.hasMarkedText() && selectedLineClipboardTextForEmptySelection() != nil
    }

    var canCutCurrentLinesWhenSelectionIsEmpty: Bool {
        canCopyCurrentLinesWhenSelectionIsEmpty && selectedLineDeletionRange() != nil
    }

    var findState: EditorFindState {
        mutableFindState
    }

    func presentFind(showsReplace: Bool) {
        var state = mutableFindState
        let wasPresented = state.isPresented
        state.isPresented = true
        state.showsReplace = showsReplace || state.showsReplace

        if !wasPresented,
           state.query.isEmpty,
           let selectedText = selectedTextForFindPrefill() {
            state.query = selectedText
        }

        updateFindState(state, preservingSelectedRange: true)
        delegate?.editorDocumentRuntimeDidRequestFindFocus(self)
    }

    func dismissFind() {
        var state = mutableFindState
        state.isPresented = false
        updateFindState(state, preservingSelectedRange: true)
    }

    func setFindReplaceVisible(_ isVisible: Bool) {
        var state = mutableFindState
        state.showsReplace = isVisible
        updateFindState(state, preservingSelectedRange: true)
    }

    func updateFindQuery(_ query: String) {
        var state = mutableFindState
        state.query = query
        updateFindState(state, selectingInitialMatch: true)
    }

    func updateFindReplacement(_ replacement: String) {
        var state = mutableFindState
        state.replacement = replacement
        updateFindState(state, preservingSelectedRange: true)
    }

    func setFindUsesRegularExpression(_ isRegex: Bool) {
        var state = mutableFindState
        state.isRegex = isRegex
        updateFindState(state, selectingInitialMatch: true)
    }

    func setFindCaseSensitive(_ isCaseSensitive: Bool) {
        var state = mutableFindState
        state.isCaseSensitive = isCaseSensitive
        updateFindState(state, selectingInitialMatch: true)
    }

    func selectNextFindMatch() {
        selectFindMatch(movingBy: 1)
    }

    func selectPreviousFindMatch() {
        selectFindMatch(movingBy: -1)
    }

    func replaceSelectedFindMatch() {
        breakUndoCoalescing()
        refreshFindMatches(preservingSelectedRange: true)

        guard let targetIndex = selectedFindMatchIndex(),
              mutableFindState.matches.indices.contains(targetIndex),
              let replacement = EditorFindEngine.replacementString(
                forFindMatchAt: targetIndex,
                in: textView.string,
                state: mutableFindState
              ) else {
            selectNextFindMatch()
            return
        }

        let replacedRange = mutableFindState.matches[targetIndex]
        textView.insertText(replacement, replacementRange: replacedRange)
        breakUndoCoalescing()

        let nextLocation = replacedRange.location + (replacement as NSString).length
        refreshFindMatches(preferredLocation: nextLocation)
        selectFindMatch(at: mutableFindState.selectedMatchIndex)
    }

    func replaceAllFindMatches() {
        breakUndoCoalescing()
        refreshFindMatches(preservingSelectedRange: true)

        guard mutableFindState.canReplaceAll,
              let replacementText = EditorFindEngine.replacingAllMatches(
                in: textView.string,
                state: mutableFindState
              ) else {
            return
        }

        let originalLength = (textView.string as NSString).length
        guard replacementText != textView.string else { return }

        textView.insertText(
            replacementText,
            replacementRange: NSRange(location: 0, length: originalLength)
        )
        breakUndoCoalescing()
        refreshFindMatches(preferredLocation: 0)
        selectFindMatch(at: mutableFindState.selectedMatchIndex)
    }

    func setSyntaxLanguageOverride(_ languageName: String?) {
        let normalizedLanguageName = languageName?.isEmpty == true ? nil : languageName
        guard session.syntaxLanguageOverride != normalizedLanguageName else { return }

        session.syntaxLanguageOverride = normalizedLanguageName
        lastSyntaxHighlightedText = nil
        lastSyntaxHighlightedThemeName = nil
        lastSyntaxHighlightedLanguageName = nil
        requestSyntaxHighlighting()
    }

    @discardableResult
    func requestImplementationJump(at event: NSEvent) -> Bool {
        guard let utf16Offset = utf16Offset(for: event) else { return false }

        delegate?.editorDocumentRuntime(self, didRequestImplementationJumpAt: utf16Offset)
        return true
    }

    func requestImplementationJumpAtCurrentSelection() {
        let selectedRange = textView.selectedRange()
        let utf16Offset = selectedRange.location == NSNotFound
            ? textView.string.utf16.count
            : selectedRange.location

        delegate?.editorDocumentRuntime(
            self,
            didRequestImplementationJumpAt: min(max(0, utf16Offset), textView.string.utf16.count)
        )
    }

    var implementationHoverRange: NSRange? {
        activeImplementationHoverRange
    }

    func updateImplementationHover(at event: NSEvent) {
        updateImplementationHover(
            windowPoint: event.locationInWindow,
            modifierFlags: event.modifierFlags
        )
    }

    func updateImplementationHoverForCurrentMouseLocation(modifierFlags: NSEvent.ModifierFlags) {
        guard let window = textView.window else {
            clearImplementationHover()
            return
        }

        updateImplementationHover(
            windowPoint: window.mouseLocationOutsideOfEventStream,
            modifierFlags: modifierFlags
        )
    }

    func clearImplementationHover() {
        guard implementationHoverTask != nil ||
              implementationHoverQueryRange != nil ||
              activeImplementationHoverRange != nil else {
            return
        }

        implementationHoverTask?.cancel()
        implementationHoverTask = nil
        implementationHoverRequestID = UUID()
        implementationHoverQueryRange = nil
        setImplementationHoverRange(nil)
    }

    func performUndo() {
        breakUndoCoalescing()

        guard textUndoManager.canUndo else { return }

        textUndoManager.undo()
    }

    func performRedo() {
        breakUndoCoalescing()

        guard textUndoManager.canRedo else { return }

        textUndoManager.redo()
    }

    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticChange,
              !isApplyingSyntaxAttributes,
              let changedTextView = notification.object as? NSTextView,
              changedTextView === textView else {
            return
        }

        delegate?.editorDocumentRuntime(self, didChangeText: textView.string)
        resetImplementationHoverState()
        updateSelection()
        refreshFindMatches(preservingSelectedRange: true)
        lineNumberRulerView?.invalidateLineNumbers()
        textView.needsDisplay = true
        diffScroller.needsDisplay = true
        scheduleSyntaxHighlighting()
        scheduleUndoCoalescingBreak()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isRestoringSelection,
              !isApplyingProgrammaticChange,
              !isApplyingSyntaxAttributes,
              let changedTextView = notification.object as? NSTextView,
              changedTextView === textView else {
            return
        }

        updateSelection()
        refreshSelectedFindMatchIndex()
    }

    private func configure(scrollView: NSScrollView, textView: RuntimeTextView) {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.runtime = self
        textView.delegate = self
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = editorFont
        textView.textColor = .labelColor
        textView.defaultParagraphStyle = tabParagraphStyle
        textView.typingAttributes = defaultTextAttributes
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.indentGuideConfiguration = indentGuideConfiguration
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
    }

    private func configure(diffScroller: EditorDiffScroller) {
        diffScroller.textProvider = { [weak self] in
            self?.textView.string ?? ""
        }
        diffScroller.jumpToLine = { [weak self] lineNumber in
            self?.jumpToLine(lineNumber)
        }
    }

    private func setText(_ text: String, registeringUndo: Bool) {
        guard textView.string != text else { return }

        isApplyingProgrammaticChange = true

        if !registeringUndo {
            textUndoManager.disableUndoRegistration()
        }

        textView.string = text

        if !registeringUndo {
            textUndoManager.enableUndoRegistration()
        }

        isApplyingProgrammaticChange = false
        lastSyntaxHighlightedText = nil
        lastSyntaxHighlightedThemeName = nil
        lastSyntaxHighlightedLanguageName = nil
        resetImplementationHoverState()
        lineNumberRulerView?.invalidateLineNumbers()
        textView.needsDisplay = true
        diffScroller.needsDisplay = true
    }

    private func restoreSelection() {
        let selectedRange = session.selectedRange.clamped(toUTF16Length: textView.string.utf16.count)
        restoreSelection(selectedRange)
    }

    private func restoreSelection(_ selectedRange: NSRange) {
        let selectedRange = selectedRange.clamped(toUTF16Length: textView.string.utf16.count)
        guard !NSEqualRanges(textView.selectedRange(), selectedRange) else { return }

        isRestoringSelection = true
        textView.setSelectedRange(selectedRange)
        isRestoringSelection = false
        invalidateSelectedLineHighlight()
    }

    private func restoreScroll() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.isRestoringScroll = true
            self.lineNumberRulerView?.invalidateLineNumbers()
            self.scrollView.contentView.scroll(
                to: self.session.scrollOrigin.clampedVertically(
                    to: self.scrollView,
                    restoresHorizontalOrigin: !self.lineWrappingMode.isWrappingEnabled
                )
            )
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.isRestoringScroll = false
            self.lineNumberRulerView?.needsDisplay = true
            self.diffScroller.needsDisplay = true
        }
    }

    private func scrollSelectionToVisible() {
        let selectedRange = textView.selectedRange()
        textView.scrollRangeToVisible(selectedRange)
        session.scrollOrigin = scrollView.contentView.bounds.origin
        delegate?.editorDocumentRuntime(self, didChangeScrollOrigin: session.scrollOrigin)
        lineNumberRulerView?.needsDisplay = true
        diffScroller.needsDisplay = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.textView.scrollRangeToVisible(selectedRange)
            self.session.scrollOrigin = self.scrollView.contentView.bounds.origin
            self.delegate?.editorDocumentRuntime(self, didChangeScrollOrigin: self.session.scrollOrigin)
            self.lineNumberRulerView?.needsDisplay = true
            self.diffScroller.needsDisplay = true
        }
    }

    func jumpToLine(_ lineNumber: Int) {
        let targetRange = EditorLineNumbering.lineRange(
            forLineNumber: lineNumber,
            in: textView.string as NSString
        )
        let selection = NSRange(location: targetRange.location, length: 0)
            .clamped(toUTF16Length: textView.string.utf16.count)

        isRestoringSelection = true
        textView.setSelectedRange(selection)
        isRestoringSelection = false
        updateSelection()
        scrollSelectionToVisible()
        textView.window?.makeFirstResponder(textView)
    }

    private func updateSelection() {
        let selectedRange = textView.selectedRange()
        session.selectedRange = selectedRange
        delegate?.editorDocumentRuntime(self, didChangeSelection: selectedRange)
        invalidateSelectedLineHighlight()
    }

    private func selectedLineRangesForIndenting(_ selectedRange: NSRange) -> [NSRange] {
        Self.selectedLineRanges(in: textView.string as NSString, selectedRanges: [selectedRange])
    }

    private func selectedLineDeletionRange() -> NSRange? {
        let selectedRanges = selectedRangesForEditing()
        guard selectedRanges.isEmpty || selectedRanges.allSatisfy({ $0.length == 0 }) else {
            return nil
        }

        let text = textView.string as NSString
        guard text.length > 0 else {
            return nil
        }

        let lineRanges = Self.selectedLineRanges(in: text, selectedRanges: selectedRanges)
        guard let firstLineRange = lineRanges.first,
              let lastLineRange = lineRanges.last else {
            return nil
        }

        var location = firstLineRange.location
        var end = NSMaxRange(lastLineRange)

        if lineRanges.count == 1,
           firstLineRange.location == text.length,
           firstLineRange.length == 0,
           let trailingLineSeparatorRange = text.trailingLineSeparatorRange {
            location = trailingLineSeparatorRange.location
            end = NSMaxRange(trailingLineSeparatorRange)
        }

        guard end > location else {
            return nil
        }

        return NSRange(location: location, length: end - location)
    }

    private func selectedLineClipboardTextForEmptySelection() -> String? {
        let selectedRanges = selectedRangesForEditing()
        guard selectedRanges.isEmpty || selectedRanges.allSatisfy({ $0.length == 0 }) else {
            return nil
        }

        let text = textView.string as NSString
        guard text.length > 0 else {
            return nil
        }

        let lineText = Self.selectedLineRanges(in: text, selectedRanges: selectedRanges)
            .map { Self.clipboardText(forLineRange: $0, in: text) }
            .joined()

        return lineText.isEmpty ? nil : lineText
    }

    private func linePasteInsertionRange() -> NSRange? {
        let selectedRanges = selectedRangesForEditing()
        guard selectedRanges.isEmpty || selectedRanges.allSatisfy({ $0.length == 0 }) else {
            return nil
        }

        let text = textView.string as NSString
        let selectedRange = textView.selectedRange().clamped(toUTF16Length: text.length)
        let lineRange = text.lineRange(for: NSRange(location: selectedRange.location, length: 0))
        return NSRange(location: lineRange.location, length: 0)
    }

    private func selectedRangesForEditing() -> [NSRange] {
        textView.selectedRanges.map(\.rangeValue)
    }

    private func indentSelectedLines(in selectedRange: NSRange) {
        let lineRanges = selectedLineRangesForIndenting(selectedRange)
        guard let firstLineRange = lineRanges.first,
              let lastLineRange = lineRanges.last else {
            return
        }

        let text = textView.string as NSString
        let editRange = NSRange(
            location: firstLineRange.location,
            length: NSMaxRange(lastLineRange) - firstLineRange.location
        )
        let indentation = tabInputSetting.indentationUnit
        var replacement = ""
        var cursor = editRange.location

        for lineRange in lineRanges {
            if lineRange.location > cursor {
                replacement += text.substring(
                    with: NSRange(location: cursor, length: lineRange.location - cursor)
                )
            }

            replacement += indentation
            replacement += text.substring(with: lineRange)
            cursor = NSMaxRange(lineRange)
        }

        let editEnd = NSMaxRange(editRange)
        if cursor < editEnd {
            replacement += text.substring(with: NSRange(location: cursor, length: editEnd - cursor))
        }

        textView.insertText(replacement, replacementRange: editRange)

        let indentationLength = (indentation as NSString).length
        let lineStarts = lineRanges.map(\.location)
        let originalEnd = NSMaxRange(selectedRange)
        let newStart = selectedRange.location + lineStarts.filter { $0 <= selectedRange.location }.count * indentationLength
        let newEnd = originalEnd + lineStarts.filter { $0 < originalEnd }.count * indentationLength
        restoreSelection(
            NSRange(location: newStart, length: max(0, newEnd - newStart))
                .clamped(toUTF16Length: textView.string.utf16.count)
        )
        updateSelection()
    }

    private func tabReplacement(at location: Int) -> String {
        switch tabInputSetting.mode {
        case .tabs:
            return "\t"
        case .spaces:
            let column = visualColumn(at: location)
            let remainder = column % tabInputSetting.width
            let spaceCount = remainder == 0 ? tabInputSetting.width : tabInputSetting.width - remainder
            return String(repeating: " ", count: spaceCount)
        }
    }

    private func visualColumn(at utf16Location: Int) -> Int {
        let text = textView.string
        let string = text as NSString
        let location = min(max(0, utf16Location), string.length)
        let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
        let prefixRange = NSRange(location: lineRange.location, length: location - lineRange.location)
        guard prefixRange.length > 0,
              let range = Range(prefixRange, in: text) else {
            return 0
        }

        var column = 0
        for character in text[range] {
            if character == "\t" {
                let remainder = column % tabInputSetting.width
                column += remainder == 0 ? tabInputSetting.width : tabInputSetting.width - remainder
            } else {
                column += 1
            }
        }

        return column
    }

    private func applyTabInputAttributes() {
        let paragraphStyle = tabParagraphStyle
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = defaultTextAttributes(paragraphStyle: paragraphStyle)

        guard let textStorage = textView.textStorage,
              textStorage.length > 0 else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let undoWasEnabled = textUndoManager.isUndoRegistrationEnabled

        isApplyingSyntaxAttributes = true
        if undoWasEnabled {
            textUndoManager.disableUndoRegistration()
        }

        textStorage.beginEditing()
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        textStorage.endEditing()

        if undoWasEnabled {
            textUndoManager.enableUndoRegistration()
        }
        isApplyingSyntaxAttributes = false
    }

    private func selectedTextForFindPrefill() -> String? {
        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        guard selectedRange.length > 0,
              selectedRange.length <= 200,
              NSMaxRange(selectedRange) <= text.length else {
            return nil
        }

        let selectedText = text.substring(with: selectedRange)
        guard !selectedText.contains("\n"),
              !selectedText.contains("\r") else {
            return nil
        }

        return selectedText
    }

    private func updateFindState(
        _ state: EditorFindState,
        preservingSelectedRange: Bool = false,
        selectingInitialMatch: Bool = false
    ) {
        var nextState = state
        applyFindMatches(to: &nextState)

        if preservingSelectedRange {
            nextState.selectedMatchIndex = EditorFindEngine.findMatchIndex(
                exactlyMatching: textView.selectedRange(),
                in: nextState.matches
            )
        } else if selectingInitialMatch {
            nextState.selectedMatchIndex = EditorFindEngine.firstMatchIndex(
                atOrAfter: textView.selectedRange().location,
                in: nextState.matches
            )
        } else if let selectedMatchIndex = mutableFindState.selectedMatchIndex,
                  nextState.matches.indices.contains(selectedMatchIndex) {
            nextState.selectedMatchIndex = selectedMatchIndex
        } else {
            nextState.selectedMatchIndex = nil
        }

        setFindState(nextState)

        if selectingInitialMatch {
            selectFindMatch(at: nextState.selectedMatchIndex)
        }
    }

    private func refreshFindMatches(
        preservingSelectedRange: Bool = false,
        preferredLocation: Int? = nil
    ) {
        guard mutableFindState.isPresented || !mutableFindState.query.isEmpty else {
            return
        }

        var nextState = mutableFindState
        applyFindMatches(to: &nextState)

        if let preferredLocation {
            nextState.selectedMatchIndex = EditorFindEngine.firstMatchIndex(
                atOrAfter: preferredLocation,
                in: nextState.matches
            )
        } else if preservingSelectedRange {
            nextState.selectedMatchIndex = EditorFindEngine.findMatchIndex(
                exactlyMatching: textView.selectedRange(),
                in: nextState.matches
            )
        } else if let selectedMatchIndex = mutableFindState.selectedMatchIndex,
                  nextState.matches.indices.contains(selectedMatchIndex) {
            nextState.selectedMatchIndex = selectedMatchIndex
        } else {
            nextState.selectedMatchIndex = nil
        }

        setFindState(nextState)
    }

    private func refreshSelectedFindMatchIndex() {
        guard mutableFindState.isPresented,
              !mutableFindState.matches.isEmpty else {
            return
        }

        var state = mutableFindState
        state.selectedMatchIndex = EditorFindEngine.findMatchIndex(
            exactlyMatching: textView.selectedRange(),
            in: state.matches
        )
        setFindState(state)
    }

    private func applyFindMatches(to state: inout EditorFindState) {
        guard !state.query.isEmpty else {
            state.matches = []
            state.selectedMatchIndex = nil
            state.errorMessage = nil
            return
        }

        do {
            state.matches = try EditorFindEngine.matches(in: textView.string, state: state)
            state.errorMessage = nil
        } catch {
            state.matches = []
            state.selectedMatchIndex = nil
            state.errorMessage = "Invalid regex"
        }
    }

    private func selectFindMatch(movingBy offset: Int) {
        refreshFindMatches(preservingSelectedRange: true)

        let matches = mutableFindState.matches
        guard !matches.isEmpty else {
            return
        }

        let selectedRange = textView.selectedRange()
        let targetIndex: Int
        if let currentIndex = EditorFindEngine.findMatchIndex(exactlyMatching: selectedRange, in: matches) {
            targetIndex = EditorFindEngine.wrappedMatchIndex(currentIndex + offset, matchCount: matches.count)
        } else if offset >= 0 {
            targetIndex = EditorFindEngine.firstMatchIndex(atOrAfter: selectedRange.location, in: matches) ?? 0
        } else {
            targetIndex = matches.lastIndex { $0.location < selectedRange.location } ?? matches.count - 1
        }

        selectFindMatch(at: targetIndex)
    }

    private func selectFindMatch(at index: Int?) {
        guard let index,
              mutableFindState.matches.indices.contains(index) else {
            var state = mutableFindState
            state.selectedMatchIndex = nil
            setFindState(state)
            return
        }

        let range = mutableFindState.matches[index]
        var state = mutableFindState
        state.selectedMatchIndex = index
        setFindState(state)

        isRestoringSelection = true
        textView.setSelectedRange(range)
        isRestoringSelection = false
        updateSelection()
        scrollSelectionToVisible()
    }

    private func selectedFindMatchIndex() -> Int? {
        EditorFindEngine.findMatchIndex(
            exactlyMatching: textView.selectedRange(),
            in: mutableFindState.matches
        )
    }

    private func setFindState(_ state: EditorFindState) {
        guard state != mutableFindState else {
            textView.needsDisplay = true
            return
        }

        mutableFindState = state
        textView.needsDisplay = true
        delegate?.editorDocumentRuntime(self, didChangeFindState: state)
    }

    private func resetImplementationHoverState() {
        implementationHoverHitCache.removeAll()
        implementationHoverMissCache.removeAll()
        clearImplementationHover()
    }

    private func updateImplementationHover(
        windowPoint: NSPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard modifierFlags.contains(.command),
              let identifierRange = identifierRange(atWindowPoint: windowPoint) else {
            clearImplementationHover()
            return
        }

        let queryRange = TextRange(location: identifierRange.location, length: identifierRange.length)
        guard implementationHoverQueryRange != queryRange else {
            if activeImplementationHoverRange != nil {
                NSCursor.pointingHand.set()
            }
            return
        }

        implementationHoverTask?.cancel()
        implementationHoverTask = nil
        implementationHoverQueryRange = queryRange
        setImplementationHoverRange(nil)

        if let cachedRange = implementationHoverHitCache[queryRange] {
            setImplementationHoverRange(cachedRange.nsRange)
            return
        }

        guard !implementationHoverMissCache.contains(queryRange) else {
            return
        }

        let requestID = UUID()
        implementationHoverRequestID = requestID
        implementationHoverTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 70_000_000)
            } catch {
                return
            }

            guard let self,
                  self.implementationHoverRequestID == requestID,
                  self.implementationHoverQueryRange == queryRange else {
                return
            }

            let resolvedRange = await self.delegate?.editorDocumentRuntime(
                self,
                implementationHoverRangeAt: queryRange.location
            )

            guard self.implementationHoverRequestID == requestID,
                  self.implementationHoverQueryRange == queryRange else {
                return
            }

            if let resolvedRange,
               resolvedRange.length > 0 {
                let hoverRange = TextRange(
                    location: resolvedRange.location,
                    length: resolvedRange.length
                )
                self.implementationHoverHitCache[queryRange] = hoverRange
                self.setImplementationHoverRange(hoverRange.nsRange)
            } else {
                self.implementationHoverMissCache.insert(queryRange)
                self.setImplementationHoverRange(nil)
            }

            self.implementationHoverTask = nil
        }
    }

    private func setImplementationHoverRange(_ range: NSRange?) {
        let textLength = textView.string.utf16.count
        let nextRange = range?.clamped(toUTF16Length: textLength)
        let validNextRange: NSRange?
        if let nextRange,
           nextRange.length > 0 {
            validNextRange = nextRange
        } else {
            validNextRange = nil
        }

        if activeImplementationHoverRange == nil && validNextRange == nil {
            return
        }

        if let activeImplementationHoverRange,
           let validNextRange,
           NSEqualRanges(activeImplementationHoverRange, validNextRange) {
            updateImplementationHoverCursor()
            return
        }

        guard let layoutManager = textView.layoutManager else {
            activeImplementationHoverRange = validNextRange
            return
        }

        let oldRange = activeImplementationHoverRange?.clamped(toUTF16Length: textLength)
        if let oldRange,
           oldRange.length > 0 {
            layoutManager.removeTemporaryAttribute(
                .underlineStyle,
                forCharacterRange: oldRange
            )
            layoutManager.removeTemporaryAttribute(
                .underlineColor,
                forCharacterRange: oldRange
            )
        }

        activeImplementationHoverRange = validNextRange

        if let validNextRange {
            layoutManager.addTemporaryAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.controlAccentColor
                ],
                forCharacterRange: validNextRange
            )
        }

        textView.needsDisplay = true
        textView.window?.invalidateCursorRects(for: textView)
        updateImplementationHoverCursor()
    }

    private func updateImplementationHoverCursor() {
        guard let window = textView.window else { return }

        let point = textView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard textView.bounds.contains(point) else { return }

        if activeImplementationHoverRange != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func identifierRange(atWindowPoint windowPoint: NSPoint) -> NSRange? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              textView.string.utf16.count > 0 else {
            return nil
        }

        let point = textView.convert(windowPoint, from: nil)
        guard textView.bounds.contains(point) else { return nil }

        let containerPoint = NSPoint(
            x: point.x - textView.textContainerOrigin.x,
            y: point.y - textView.textContainerOrigin.y
        )

        layoutManager.ensureLayout(for: textContainer)
        guard layoutManager.numberOfGlyphs > 0 else { return nil }

        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let glyphRect = layoutManager
            .boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            .insetBy(dx: -1, dy: -2)
        guard glyphRect.contains(containerPoint) else { return nil }

        return identifierRange(containingUTF16Offset: layoutManager.characterIndexForGlyph(at: glyphIndex))
    }

    private func identifierRange(containingUTF16Offset utf16Offset: Int) -> NSRange? {
        let string = textView.string as NSString
        guard utf16Offset >= 0,
              utf16Offset < string.length,
              Self.isIdentifierCharacter(string.character(at: utf16Offset)) else {
            return nil
        }

        var start = utf16Offset
        while start > 0 && Self.isIdentifierCharacter(string.character(at: start - 1)) {
            start -= 1
        }

        var end = utf16Offset + 1
        while end < string.length && Self.isIdentifierCharacter(string.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    private static func isIdentifierCharacter(_ character: unichar) -> Bool {
        let scalar = UnicodeScalar(Int(character))
        guard let scalar else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$"
    }

    private func utf16Offset(for event: NSEvent) -> Int? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return nil
        }

        let point = textView.convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textView.textContainerOrigin.x,
            y: point.y - textView.textContainerOrigin.y
        )

        layoutManager.ensureLayout(for: textContainer)

        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return min(max(0, characterIndex), textView.string.utf16.count)
    }

    private func invalidateSelectedLineHighlight() {
        textView.needsDisplay = true
        lineNumberRulerView?.needsDisplay = true
        diffScroller.needsDisplay = true
    }

    private var defaultTextAttributes: [NSAttributedString.Key: Any] {
        defaultTextAttributes(paragraphStyle: tabParagraphStyle)
    }

    private func defaultTextAttributes(paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: editorFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private var tabParagraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.defaultTabInterval = tabDisplayInterval
        paragraphStyle.lineHeightMultiple = editorLineHeightMultiple
        paragraphStyle.tabStops = []
        return paragraphStyle.copy() as? NSParagraphStyle ?? NSParagraphStyle.default
    }

    private var tabDisplayInterval: CGFloat {
        max(1, editorCharacterWidth * CGFloat(tabInputSetting.width))
    }

    private var editorCharacterWidth: CGFloat {
        max(1, (" " as NSString).size(withAttributes: [.font: editorFont]).width)
    }

    private var indentGuideConfiguration: EditorIndentGuideConfiguration {
        EditorIndentGuideConfiguration(
            tabWidth: tabInputSetting.width,
            levelWidth: tabDisplayInterval
        )
    }

    private func applyIndentGuideConfiguration() {
        textView.indentGuideConfiguration = indentGuideConfiguration
    }

    private func attributes(
        for role: SyntaxHighlightRole,
        themeName: String
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: SyntaxHighlightPalette.color(for: role, themeName: themeName),
            .font: editorFont
        ]

        switch role {
        case .comment:
            attributes[.font] = NSFontManager.shared.convert(editorFont, toHaveTrait: .italicFontMask)
        case .keyword, .type, .tag:
            attributes[.font] = NSFontManager.shared.convert(editorFont, toHaveTrait: .boldFontMask)
        case .string, .number, .function, .property, .operator, .punctuation, .attribute, .constant, .variable:
            break
        }

        return attributes
    }

    private func scheduleSyntaxHighlighting() {
        guard !textView.hasMarkedText() else { return }

        syntaxHighlightTask?.cancel()
        syntaxHighlightGeneration += 1
        syntaxHighlightTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }

            guard let self,
                  !self.textView.hasMarkedText() else {
                return
            }

            self.requestSyntaxHighlighting()
        }
    }

    private func refreshSyntaxHighlightingIfNeeded() {
        let themeName = SyntaxHighlightingService.themeName(for: textView.effectiveAppearance)
        let languageName = effectiveSyntaxLanguageName
        guard lastSyntaxHighlightedText != textView.string ||
                lastSyntaxHighlightedThemeName != themeName ||
                lastSyntaxHighlightedLanguageName != languageName else {
            return
        }

        requestSyntaxHighlighting(themeName: themeName)
    }

    private func requestSyntaxHighlighting(themeName: String? = nil) {
        syntaxHighlightTask?.cancel()
        syntaxHighlightTask = nil

        guard !textView.hasMarkedText() else {
            return
        }

        let text = textView.string
        let themeName = themeName ?? SyntaxHighlightingService.themeName(for: textView.effectiveAppearance)
        let languageName = effectiveSyntaxLanguageName
        syntaxHighlightGeneration += 1

        if text.utf16.count > SyntaxHighlightingService.maximumHighlightedUTF16Length {
            disableSyntaxHighlightingForLargeDocument(
                text: text,
                themeName: themeName,
                languageName: languageName
            )
            return
        }

        let service = syntaxHighlightingService
        let generation = syntaxHighlightGeneration

        syntaxHighlightTask = Task { [weak self] in
            let runs = await service.highlightedRuns(for: text, languageName: languageName)

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self,
                      generation == self.syntaxHighlightGeneration,
                      self.textView.string == text,
                      !self.textView.hasMarkedText() else {
                    return
                }

                self.applySyntaxHighlighting(
                    runs: runs,
                    text: text,
                    themeName: themeName,
                    languageName: languageName
                )
            }
        }
    }

    private func applySyntaxHighlighting(
        runs: [SyntaxHighlightRun],
        text: String,
        themeName: String,
        languageName: String?
    ) {
        guard let textStorage = textView.textStorage else {
            return
        }

        let selectedRange = textView.selectedRange()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let undoWasEnabled = textUndoManager.isUndoRegistrationEnabled

        isApplyingSyntaxAttributes = true
        if undoWasEnabled {
            textUndoManager.disableUndoRegistration()
        }

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.setAttributes(defaultTextAttributes, range: fullRange)
            for run in runs {
                let range = run.range
                if range.location >= 0,
                   range.length > 0,
                   NSMaxRange(range) <= fullRange.length {
                    textStorage.addAttributes(
                        attributes(for: run.role, themeName: themeName),
                        range: range
                    )
                }
            }
        }
        textStorage.endEditing()

        if undoWasEnabled {
            textUndoManager.enableUndoRegistration()
        }
        textView.typingAttributes = defaultTextAttributes
        restoreSelection(selectedRange)
        isApplyingSyntaxAttributes = false

        lastSyntaxHighlightedText = text
        lastSyntaxHighlightedThemeName = themeName
        lastSyntaxHighlightedLanguageName = languageName
        isSyntaxHighlightingDisabledForLargeDocument = false
    }

    private func disableSyntaxHighlightingForLargeDocument(
        text: String,
        themeName: String,
        languageName: String?
    ) {
        if !isSyntaxHighlightingDisabledForLargeDocument {
            applySyntaxHighlighting(
                runs: [],
                text: text,
                themeName: themeName,
                languageName: languageName
            )
        } else {
            lastSyntaxHighlightedText = text
            lastSyntaxHighlightedThemeName = themeName
            lastSyntaxHighlightedLanguageName = languageName
        }

        isSyntaxHighlightingDisabledForLargeDocument = true
    }

    private var effectiveSyntaxLanguageName: String? {
        session.syntaxLanguageOverride ?? inferredSyntaxLanguageName
    }

    private func observeBoundsChanges(in clipView: NSClipView) {
        guard observedClipView !== clipView else { return }

        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: observedClipView
            )
        }

        observedClipView = clipView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        guard !isRestoringScroll,
              let clipView = notification.object as? NSClipView else {
            return
        }

        let scrollOrigin = clipView.bounds.origin
        session.scrollOrigin = scrollOrigin
        delegate?.editorDocumentRuntime(self, didChangeScrollOrigin: scrollOrigin)
        lineNumberRulerView?.needsDisplay = true
    }

    private static func makeEditorViews() -> (
        scrollView: NSScrollView,
        textView: RuntimeTextView,
        diffScroller: EditorDiffScroller
    ) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        )

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = RuntimeTextView(frame: .zero, textContainer: textContainer)
        let scrollView = NSScrollView()
        let diffScroller = EditorDiffScroller()
        let lineNumberRulerView = EditorLineNumberRulerView(
            scrollView: scrollView,
            textView: textView
        )

        scrollView.documentView = textView
        scrollView.verticalScroller = diffScroller
        scrollView.verticalRulerView = lineNumberRulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        return (scrollView, textView, diffScroller)
    }

    private func scheduleUndoCoalescingBreak() {
        guard !textView.hasMarkedText() else { return }

        undoCoalescingBreakTask?.cancel()
        undoCoalescingBreakTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 650_000_000)
            } catch {
                return
            }

            guard let self,
                  !self.textView.hasMarkedText() else {
                return
            }

            self.textView.breakUndoCoalescing()
            self.undoCoalescingBreakTask = nil
        }
    }

    private static func commandTitle(base: String, actionName: String) -> String {
        guard !actionName.isEmpty else { return base }
        return "\(base) \(actionName)"
    }

    private static func clipboardText(forLineRange lineRange: NSRange, in string: NSString) -> String {
        guard lineRange.length > 0 else {
            return "\n"
        }

        let lineText = string.substring(with: lineRange)
        if NSMaxRange(lineRange) == string.length,
           !lineText.hasLineSeparatorSuffix {
            return lineText + "\n"
        }

        return lineText
    }

    private static func isLineClipboardText(_ text: String) -> Bool {
        let string = text as NSString
        guard let trailingLineSeparatorRange = string.trailingLineSeparatorRange,
              NSMaxRange(trailingLineSeparatorRange) == string.length else {
            return false
        }

        guard trailingLineSeparatorRange.location > 0 else {
            return true
        }

        let previousCharacter = string.character(at: trailingLineSeparatorRange.location - 1)
        return previousCharacter != 10 && previousCharacter != 13
    }

    static func cursorPosition(in text: String, selectedRange: NSRange) -> EditorCursorPosition {
        let location = selectedRange.location == NSNotFound ? text.utf16.count : selectedRange.location
        let clampedLocation = min(max(0, location), text.utf16.count)
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clampedLocation)
        let cursorIndex = String.Index(utf16Index, within: text) ?? text.endIndex
        let prefix = text[..<cursorIndex]
        let line = prefix.reduce(1) { partialResult, character in
            character == "\n" ? partialResult + 1 : partialResult
        }
        let lineStart = prefix.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let column = text[lineStart..<cursorIndex].count + 1

        return EditorCursorPosition(line: line, column: column)
    }

    static func selectedLineRanges(in text: String, selectedRanges: [NSRange]) -> [NSRange] {
        selectedLineRanges(in: text as NSString, selectedRanges: selectedRanges)
    }

    private static func selectedLineRanges(in string: NSString, selectedRanges: [NSRange]) -> [NSRange] {
        let textLength = string.length
        let ranges = selectedRanges.isEmpty
            ? [NSRange(location: 0, length: 0)]
            : selectedRanges
        var selectedLineRanges: [NSRange] = []
        var selectedLineStarts = Set<Int>()

        for range in ranges {
            let range = range.clamped(toUTF16Length: textLength)
            let startLocation = range.location
            let endLocation = range.length == 0
                ? startLocation
                : max(startLocation, NSMaxRange(range) - 1)
            var lineStart = string.lineRange(
                for: NSRange(location: startLocation, length: 0)
            ).location

            while lineStart <= endLocation {
                let lineRange = string.lineRange(
                    for: NSRange(location: min(lineStart, textLength), length: 0)
                )
                if selectedLineStarts.insert(lineRange.location).inserted {
                    selectedLineRanges.append(lineRange)
                }

                let nextLineStart = NSMaxRange(lineRange)
                guard range.length > 0,
                      nextLineStart > lineStart,
                      nextLineStart <= textLength,
                      nextLineStart <= endLocation else {
                    break
                }

                lineStart = nextLineStart
            }
        }

        return selectedLineRanges.sorted { $0.location < $1.location }
    }
}

private extension NSRange {
    func clamped(toUTF16Length length: Int) -> NSRange {
        guard location != NSNotFound else {
            return NSRange(location: length, length: 0)
        }

        let clampedLocation = min(max(0, location), length)
        let maximumLength = max(0, length - clampedLocation)
        return NSRange(location: clampedLocation, length: min(max(0, self.length), maximumLength))
    }
}

private extension NSString {
    var trailingLineSeparatorRange: NSRange? {
        guard length > 0 else {
            return nil
        }

        let lastIndex = length - 1
        let lastCharacter = character(at: lastIndex)
        if lastCharacter == 10 {
            if lastIndex > 0,
               character(at: lastIndex - 1) == 13 {
                return NSRange(location: lastIndex - 1, length: 2)
            }

            return NSRange(location: lastIndex, length: 1)
        }

        if lastCharacter == 13 {
            return NSRange(location: lastIndex, length: 1)
        }

        return nil
    }
}

private extension String {
    var hasLineSeparatorSuffix: Bool {
        guard let last else {
            return false
        }

        return last == "\n" || last == "\r"
    }
}

private extension CGPoint {
    func clampedVertically(
        to scrollView: NSScrollView,
        restoresHorizontalOrigin: Bool = false
    ) -> CGPoint {
        guard let documentView = scrollView.documentView else { return .zero }

        let maximumY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)

        return CGPoint(
            x: restoresHorizontalOrigin ? x : scrollView.contentView.bounds.origin.x,
            y: min(max(0, y), maximumY)
        )
    }
}
