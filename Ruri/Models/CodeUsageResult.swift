//
//  CodeUsageResult.swift
//  ruri
//

import Foundation

struct CodeUsageResult: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let url: URL
        let location: Int
        let length: Int
    }

    let url: URL
    let relativePath: String
    let fileName: String
    let lineNumber: Int
    let column: Int
    let lineText: String
    let matchRange: TextRange
    let lineMatchRange: TextRange

    nonisolated var id: ID {
        ID(url: url.standardizedFileURL, location: matchRange.location, length: matchRange.length)
    }

    nonisolated var displayParentPath: String {
        let parentPath = (relativePath as NSString).deletingLastPathComponent
        return parentPath.isEmpty || parentPath == "." ? "." : parentPath
    }

    nonisolated var isInTestDirectory: Bool {
        SearchResultPathPolicy.isFileInTestDirectory(relativePath)
    }

    nonisolated static func result(
        for target: SymbolNavigationTarget,
        text: String,
        projectURL: URL
    ) -> CodeUsageResult {
        result(url: target.url, range: target.range, text: text, projectURL: projectURL)
    }

    nonisolated static func result(
        url: URL,
        range: TextRange,
        text: String,
        projectURL: URL
    ) -> CodeUsageResult {
        let range = range.nsRange.clamped(toUTF16Length: text.utf16.count)
        let string = text as NSString
        let textLength = string.length
        let matchLocation = min(range.location, textLength)
        let lineRange = string.lineRange(for: NSRange(location: matchLocation, length: 0))
        let rawLineText = string.substring(with: lineRange)
        let lineText = rawLineText.removingTrailingLineSeparators()
        let lineTextLength = (lineText as NSString).length
        let lineMatchLocation = min(max(0, matchLocation - lineRange.location), lineTextLength)
        let lineMatchLength = min(range.length, max(0, lineTextLength - lineMatchLocation))

        return CodeUsageResult(
            url: url.standardizedFileURL,
            relativePath: FileURLRewriter.relativePath(from: projectURL, to: url) ?? url.lastPathComponent,
            fileName: url.lastPathComponent,
            lineNumber: lineNumber(at: matchLocation, in: string),
            column: columnNumber(in: text, lineStartLocation: lineRange.location, matchLocation: matchLocation),
            lineText: lineText,
            matchRange: TextRange(location: range.location, length: range.length),
            lineMatchRange: TextRange(location: lineMatchLocation, length: lineMatchLength)
        )
    }

    nonisolated static func sorted(_ results: [CodeUsageResult]) -> [CodeUsageResult] {
        results.sorted { lhs, rhs in
            if lhs.isInTestDirectory != rhs.isInTestDirectory {
                return !lhs.isInTestDirectory && rhs.isInTestDirectory
            }

            let pathOrder = lhs.relativePath.localizedStandardCompare(rhs.relativePath)
            if pathOrder != .orderedSame {
                return pathOrder == .orderedAscending
            }

            if lhs.lineNumber != rhs.lineNumber {
                return lhs.lineNumber < rhs.lineNumber
            }

            if lhs.column != rhs.column {
                return lhs.column < rhs.column
            }

            return lhs.matchRange.location < rhs.matchRange.location
        }
    }

    nonisolated private static func lineNumber(at location: Int, in string: NSString) -> Int {
        guard location > 0,
              string.length > 0 else {
            return 1
        }

        let cappedLocation = min(location, string.length)
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

    nonisolated private static func columnNumber(
        in text: String,
        lineStartLocation: Int,
        matchLocation: Int
    ) -> Int {
        let utf16Length = text.utf16.count
        let lineStartOffset = min(max(0, lineStartLocation), utf16Length)
        let matchOffset = min(max(lineStartOffset, matchLocation), utf16Length)
        let lineStartUTF16Index = text.utf16.index(text.utf16.startIndex, offsetBy: lineStartOffset)
        let matchUTF16Index = text.utf16.index(text.utf16.startIndex, offsetBy: matchOffset)

        guard let lineStartIndex = String.Index(lineStartUTF16Index, within: text),
              let matchIndex = String.Index(matchUTF16Index, within: text) else {
            return matchOffset - lineStartOffset + 1
        }

        return text[lineStartIndex..<matchIndex].count + 1
    }

}

private extension String {
    func removingTrailingLineSeparators() -> String {
        var value = self

        while value.hasSuffix("\n") || value.hasSuffix("\r") {
            value.removeLast()
        }

        return value
    }
}
