//
//  ProjectFileSearchIndexStatusState.swift
//  ruri
//

import Foundation

enum ProjectFileSearchIndexStatusState: Equatable, Sendable {
    case inactive
    case indexing
    case ready(fileCount: Int)
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
            "Files"
        case .indexing:
            "Files Indexing"
        case .ready(let fileCount):
            "\(fileCount) File\(fileCount == 1 ? "" : "s")"
        case .failed:
            "Files Error"
        }
    }

    var detail: String {
        switch self {
        case .inactive:
            "No file search index is active for this project."
        case .indexing:
            "Indexing project files for Double Shift search."
        case .ready(let fileCount):
            "\(fileCount) file\(fileCount == 1 ? "" : "s") indexed for Double Shift search."
        case .failed(let message):
            "File search index failed: \(message)"
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
