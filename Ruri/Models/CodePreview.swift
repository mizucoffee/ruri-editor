//
//  CodePreview.swift
//  ruri
//

import Foundation

nonisolated struct CodePreviewRequest: Equatable, Sendable {
    let url: URL
    let matchRange: TextRange
    let lineNumber: Int
}

struct CodePreviewDocument: Equatable {
    let request: CodePreviewRequest
    let text: String
    let languageName: String?
    let syntaxRuns: [SyntaxHighlightRun]
}

enum CodePreviewFailure: Equatable, Sendable {
    case unreadable
    case fileTooLarge
}

extension ProjectTextSearchResult {
    nonisolated var codePreviewRequest: CodePreviewRequest {
        CodePreviewRequest(url: url, matchRange: matchRange, lineNumber: lineNumber)
    }
}
