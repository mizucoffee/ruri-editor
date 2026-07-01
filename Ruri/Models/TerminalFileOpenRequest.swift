//
//  TerminalFileOpenRequest.swift
//  ruri
//

import Foundation

struct TerminalFileOpenRequest: Equatable, Sendable {
    let url: URL
    let lineNumber: Int?

    init(url: URL, lineNumber: Int? = nil) {
        self.url = url.standardizedFileURL
        self.lineNumber = lineNumber
    }
}
