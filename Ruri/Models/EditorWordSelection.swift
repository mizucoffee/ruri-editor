//
//  EditorWordSelection.swift
//  ruri
//

import Foundation

enum EditorWordSelection {
    /// Selection range for word-granularity (double-click) selection.
    /// Shrinks the selection to a single identifier segment so that dots act as
    /// boundaries (double-clicking `editor` in `editor.gitSnapshot` selects only
    /// `editor`). Clicks outside identifiers (whitespace, brackets, operators)
    /// return `fallback`, preserving AppKit's default behavior.
    static func wordSelectionRange(in string: NSString, proposedRange: NSRange, fallback: NSRange) -> NSRange {
        guard proposedRange.location != NSNotFound,
              proposedRange.location >= 0,
              NSMaxRange(proposedRange) <= string.length else {
            return fallback
        }

        if proposedRange.length == 0 {
            guard let range = identifierRange(in: string, aroundUTF16Offset: proposedRange.location) else {
                return fallback
            }

            return range
        }

        let startRange = identifierRange(in: string, aroundUTF16Offset: proposedRange.location)
        let endRange = EditorOccurrenceHighlighter.identifierRange(
            in: string,
            containingUTF16Offset: NSMaxRange(proposedRange) - 1
        )
        guard startRange != nil || endRange != nil else {
            return fallback
        }

        let start = min(startRange?.location ?? fallback.location, proposedRange.location)
        let end = max(endRange.map(NSMaxRange) ?? NSMaxRange(fallback), NSMaxRange(proposedRange))
        guard start <= end else { return fallback }

        return NSRange(location: start, length: end - start)
    }

    /// Identifier range containing the offset; when the offset sits just past the
    /// end of an identifier (e.g. a double-click at a word's trailing boundary),
    /// falls back to the identifier ending there.
    private static func identifierRange(in string: NSString, aroundUTF16Offset utf16Offset: Int) -> NSRange? {
        if let range = EditorOccurrenceHighlighter.identifierRange(in: string, containingUTF16Offset: utf16Offset) {
            return range
        }

        return EditorOccurrenceHighlighter.identifierRange(in: string, containingUTF16Offset: utf16Offset - 1)
    }
}
