//
//  ReviewDiffCodeNavigationRequest.swift
//  ruri
//

import Foundation

nonisolated enum ReviewDiffCodeNavigationSide: Equatable, Sendable {
    case old
    case new
}

nonisolated struct ReviewDiffCodeNavigationRequest: Equatable, Sendable {
    let fileURL: URL
    let side: ReviewDiffCodeNavigationSide
    let lineNumber: Int
    let utf16Column: Int

    init(
        fileURL: URL,
        side: ReviewDiffCodeNavigationSide = .new,
        lineNumber: Int,
        utf16Column: Int
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.side = side
        self.lineNumber = lineNumber
        self.utf16Column = utf16Column
    }

    static func utf16Offset(lineNumber: Int, utf16Column: Int, in text: String) -> Int? {
        guard let lineContentRange = lineContentRange(lineNumber: lineNumber, in: text) else {
            return nil
        }

        let clampedColumn = min(max(0, utf16Column), lineContentRange.length)
        return lineContentRange.location + clampedColumn
    }

    static func lineContentRange(lineNumber: Int, in text: String) -> NSRange? {
        guard lineNumber > 0 else { return nil }

        let string = text as NSString
        var currentLineNumber = 1
        var lineStartLocation = 0

        while currentLineNumber < lineNumber {
            guard lineStartLocation < string.length else { return nil }

            let lineRange = string.lineRange(for: NSRange(location: lineStartLocation, length: 0))
            let nextLineStartLocation = NSMaxRange(lineRange)
            guard nextLineStartLocation > lineStartLocation else { return nil }

            lineStartLocation = nextLineStartLocation
            currentLineNumber += 1
        }

        guard lineStartLocation <= string.length else { return nil }

        let lineRange = string.lineRange(for: NSRange(location: lineStartLocation, length: 0))
        let rawLineText = string.substring(with: lineRange)
        let lineTextLength = (rawLineText.removingTrailingLineSeparators() as NSString).length
        return NSRange(location: lineStartLocation, length: lineTextLength)
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
