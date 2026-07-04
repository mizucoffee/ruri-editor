//
//  EditorBracketMatcher.swift
//  ruri
//

import Foundation

enum EditorBracketMatcher {
    static let maximumScanUTF16Length = 1_000_000

    struct BracketKind: Equatable {
        let counterpart: unichar
        let isOpening: Bool
    }

    static func bracketKind(of character: unichar) -> BracketKind? {
        guard let scalar = UnicodeScalar(character) else { return nil }

        switch scalar {
        case "(":
            return BracketKind(counterpart: utf16(")"), isOpening: true)
        case ")":
            return BracketKind(counterpart: utf16("("), isOpening: false)
        case "[":
            return BracketKind(counterpart: utf16("]"), isOpening: true)
        case "]":
            return BracketKind(counterpart: utf16("["), isOpening: false)
        case "{":
            return BracketKind(counterpart: utf16("}"), isOpening: true)
        case "}":
            return BracketKind(counterpart: utf16("{"), isOpening: false)
        default:
            return nil
        }
    }

    static func targetBracketOffset(in string: NSString, selectedRange: NSRange) -> Int? {
        guard selectedRange.location != NSNotFound,
              selectedRange.location >= 0,
              NSMaxRange(selectedRange) <= string.length else {
            return nil
        }

        if selectedRange.length == 0 {
            if isBracket(at: selectedRange.location, in: string) {
                return selectedRange.location
            }

            if isBracket(at: selectedRange.location - 1, in: string) {
                return selectedRange.location - 1
            }

            return nil
        }

        guard selectedRange.length == 1,
              isBracket(at: selectedRange.location, in: string) else {
            return nil
        }

        return selectedRange.location
    }

    static func matchedBracketRanges(in string: NSString, selectedRange: NSRange) -> [NSRange] {
        guard string.length <= maximumScanUTF16Length,
              let targetOffset = targetBracketOffset(in: string, selectedRange: selectedRange),
              let kind = bracketKind(of: string.character(at: targetOffset)),
              let counterpartOffset = counterpartOffset(of: kind, at: targetOffset, in: string) else {
            return []
        }

        return [
            NSRange(location: min(targetOffset, counterpartOffset), length: 1),
            NSRange(location: max(targetOffset, counterpartOffset), length: 1),
        ]
    }

    private static func isBracket(at offset: Int, in string: NSString) -> Bool {
        guard offset >= 0, offset < string.length else { return false }

        return bracketKind(of: string.character(at: offset)) != nil
    }

    private static func counterpartOffset(of kind: BracketKind, at offset: Int, in string: NSString) -> Int? {
        let own = string.character(at: offset)
        var depth = 1
        var index = kind.isOpening ? offset + 1 : offset - 1

        while index >= 0 && index < string.length {
            let character = string.character(at: index)

            if character == own {
                depth += 1
            } else if character == kind.counterpart {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index += kind.isOpening ? 1 : -1
        }

        return nil
    }

    private static func utf16(_ scalar: UnicodeScalar) -> unichar {
        unichar(scalar.value)
    }
}
