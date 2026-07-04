//
//  EditorOccurrenceHighlighter.swift
//  ruri
//

import Foundation

enum EditorOccurrenceHighlighter {
    static let maximumScanUTF16Length = 1_000_000

    static func isIdentifierCharacter(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(character)) else { return false }

        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$"
    }

    static func identifierRange(in string: NSString, containingUTF16Offset utf16Offset: Int) -> NSRange? {
        guard utf16Offset >= 0,
              utf16Offset < string.length,
              isIdentifierCharacter(string.character(at: utf16Offset)) else {
            return nil
        }

        var start = utf16Offset
        while start > 0 && isIdentifierCharacter(string.character(at: start - 1)) {
            start -= 1
        }

        var end = utf16Offset + 1
        while end < string.length && isIdentifierCharacter(string.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: end - start)
    }

    static func targetIdentifierRange(in string: NSString, selectedRange: NSRange) -> NSRange? {
        guard selectedRange.location != NSNotFound,
              selectedRange.location >= 0,
              NSMaxRange(selectedRange) <= string.length else {
            return nil
        }

        if selectedRange.length == 0 {
            if let range = identifierRange(in: string, containingUTF16Offset: selectedRange.location) {
                return range
            }

            return identifierRange(in: string, containingUTF16Offset: selectedRange.location - 1)
        }

        guard let range = identifierRange(in: string, containingUTF16Offset: selectedRange.location),
              NSEqualRanges(range, selectedRange) else {
            return nil
        }

        return range
    }

    static func occurrenceRanges(in string: NSString, selectedRange: NSRange) -> [NSRange] {
        guard string.length <= maximumScanUTF16Length,
              let targetRange = targetIdentifierRange(in: string, selectedRange: selectedRange) else {
            return []
        }

        let identifier = string.substring(with: targetRange)
        var matches: [NSRange] = []
        var searchLocation = 0

        while searchLocation < string.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: string.length - searchLocation
            )
            let matchRange = string.range(
                of: identifier,
                options: [.literal],
                range: searchRange
            )

            guard matchRange.location != NSNotFound,
                  matchRange.length > 0 else {
                break
            }

            if isWholeWordMatch(matchRange, in: string) {
                matches.append(matchRange)
            }

            searchLocation = NSMaxRange(matchRange)
        }

        return matches
    }

    private static func isWholeWordMatch(_ range: NSRange, in string: NSString) -> Bool {
        if range.location > 0,
           isIdentifierCharacter(string.character(at: range.location - 1)) {
            return false
        }

        let end = NSMaxRange(range)
        if end < string.length,
           isIdentifierCharacter(string.character(at: end)) {
            return false
        }

        return true
    }
}
