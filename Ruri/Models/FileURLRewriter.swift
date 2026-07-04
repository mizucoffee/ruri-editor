//
//  FileURLRewriter.swift
//  ruri
//

import Foundation

nonisolated enum FileURLRewriter {
    static func urlsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedPath(lhs) == normalizedPath(rhs)
    }

    static func rewrittenURL(
        _ url: URL,
        replacing oldRootURL: URL,
        with newRootURL: URL
    ) -> URL? {
        guard let relativePath = relativePath(from: oldRootURL, to: url) else { return nil }

        if relativePath.isEmpty {
            return newRootURL.standardizedFileURL
        }

        return newRootURL.appending(path: relativePath).standardizedFileURL
    }

    static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)

        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }

    // String variant for raw file-system event paths. Unlike the URL variant it
    // must not round-trip through URL(filePath:), which would resolve relative
    // paths against the current directory instead of dropping them.
    static func normalizedPath(_ path: String) -> String {
        var normalizedPath = NSString(string: path).standardizingPath

        while normalizedPath.count > 1 && normalizedPath.hasSuffix("/") {
            normalizedPath.removeLast()
        }

        return normalizedPath
    }

    // Returns "" when the paths are equal and nil when targetURL is not a
    // descendant of rootURL. Callers that need a display fallback or a "."
    // form apply it explicitly at the call site.
    static func relativePath(from rootURL: URL, to targetURL: URL) -> String? {
        let rootPath = normalizedPath(rootURL)
        let targetPath = normalizedPath(targetURL)

        if targetPath == rootPath {
            return ""
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard targetPath.hasPrefix(rootPrefix) else { return nil }

        return String(targetPath.dropFirst(rootPrefix.count))
    }

    static func isDescendantOrSame(_ url: URL, of rootURL: URL) -> Bool {
        relativePath(from: rootURL, to: url) != nil
    }
}
