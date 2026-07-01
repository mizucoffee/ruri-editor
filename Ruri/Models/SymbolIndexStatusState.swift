//
//  SymbolIndexStatusState.swift
//  ruri
//

import Foundation

enum SymbolIndexStatusState: Equatable, Sendable {
    case inactive
    case indexing
    case ready(symbolCount: Int, fileCount: Int)
    case failed(message: String)

    enum Severity: Sendable {
        case inactive
        case info
        case ready
        case error
    }

    var title: String {
        switch self {
        case .inactive:
            "Symbols"
        case .indexing:
            "Indexing"
        case .ready(let symbolCount, _):
            "\(symbolCount) Symbol\(symbolCount == 1 ? "" : "s")"
        case .failed:
            "Symbols Error"
        }
    }

    var detail: String {
        switch self {
        case .inactive:
            "No Java symbol index is active for this project."
        case .indexing:
            "Preparing Java symbol navigation."
        case .ready(let symbolCount, let fileCount):
            "\(symbolCount) symbol\(symbolCount == 1 ? "" : "s") indexed from \(fileCount) file\(fileCount == 1 ? "" : "s")."
        case .failed(let message):
            "Symbol index failed: \(message)"
        }
    }

    var systemImageName: String {
        switch self {
        case .inactive:
            "circle"
        case .indexing:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark.circle"
        case .failed:
            "xmark.octagon"
        }
    }

    var severity: Severity {
        switch self {
        case .inactive:
            .inactive
        case .indexing:
            .info
        case .ready:
            .ready
        case .failed:
            .error
        }
    }
}
