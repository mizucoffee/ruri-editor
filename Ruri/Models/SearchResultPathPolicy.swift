//
//  SearchResultPathPolicy.swift
//  ruri
//

import Foundation

enum SearchResultPathPolicy {
    private static func pathComponents(_ path: String) -> [String] {
        let normalizedPath = path
            .replacingOccurrences(of: "\\", with: "/")
        return normalizedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
    }

    nonisolated static func isFileInTestDirectory(_ relativePath: String) -> Bool {
        let components = pathComponents(relativePath)
        guard components.count >= 2 else { return false }
        return components.dropLast().contains { isTestDirectory($0) }
    }

    nonisolated static func isDirectoryInTestDirectory(_ relativeParentPath: String) -> Bool {
        let components = pathComponents(relativeParentPath)
        return components.contains { isTestDirectory($0) }
    }

    private static func isTestDirectory(_ component: String) -> Bool {
        component == "test" || component == "tests"
    }
}
