//
//  EditorFindEngine.swift
//  ruri
//

import Foundation

enum EditorFindEngine {
    static func matches(in text: String, state: EditorFindState) throws -> [NSRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if state.isRegex {
            let regex = try regularExpression(for: state)
            return regex.matches(in: text, options: [], range: fullRange)
                .map(\.range)
                .filter { $0.length > 0 }
        }

        let options: NSString.CompareOptions = state.isCaseSensitive
            ? []
            : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchLocation = 0

        while searchLocation < nsText.length {
            let searchRange = NSRange(
                location: searchLocation,
                length: nsText.length - searchLocation
            )
            let matchRange = nsText.range(
                of: state.query,
                options: options,
                range: searchRange
            )

            guard matchRange.location != NSNotFound,
                  matchRange.length > 0 else {
                break
            }

            matches.append(matchRange)
            searchLocation = NSMaxRange(matchRange)
        }

        return matches
    }

    static func findMatchIndex(exactlyMatching range: NSRange, in matches: [NSRange]) -> Int? {
        matches.firstIndex { NSEqualRanges($0, range) }
    }

    static func firstMatchIndex(atOrAfter location: Int, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex { $0.location >= location } ?? 0
    }

    static func wrappedMatchIndex(_ index: Int, matchCount: Int) -> Int {
        guard matchCount > 0 else { return 0 }
        return (index % matchCount + matchCount) % matchCount
    }

    static func replacementString(
        forFindMatchAt index: Int,
        in text: String,
        state: EditorFindState
    ) -> String? {
        guard state.matches.indices.contains(index) else {
            return nil
        }

        if state.isRegex {
            return regexReplacementPairs(in: text, state: state).first { pair in
                NSEqualRanges(pair.range, state.matches[index])
            }?.replacement
        }

        return state.replacement
    }

    static func replacingAllMatches(in text: String, state: EditorFindState) -> String? {
        guard !state.matches.isEmpty else {
            return text
        }

        let mutableText = NSMutableString(string: text)

        if state.isRegex {
            let pairs = regexReplacementPairs(in: text, state: state)
            guard pairs.count == state.matches.count else {
                return nil
            }

            for pair in pairs.reversed() {
                mutableText.replaceCharacters(in: pair.range, with: pair.replacement)
            }
        } else {
            for range in state.matches.reversed() {
                mutableText.replaceCharacters(in: range, with: state.replacement)
            }
        }

        return mutableText as String
    }

    private static func regularExpression(for state: EditorFindState) throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if !state.isCaseSensitive {
            options.insert(.caseInsensitive)
        }
        return try NSRegularExpression(pattern: state.query, options: options)
    }

    private static func regexReplacementPairs(
        in text: String,
        state: EditorFindState
    ) -> [(range: NSRange, replacement: String)] {
        guard state.isRegex,
              let regex = try? regularExpression(for: state) else {
            return []
        }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, options: [], range: fullRange)
            .filter { $0.range.length > 0 }
            .map { result in
                (
                    range: result.range,
                    replacement: regex.replacementString(
                        for: result,
                        in: text,
                        offset: 0,
                        template: state.replacement
                    )
                )
            }
    }
}
