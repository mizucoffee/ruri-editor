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
        let path = normalizedPath(url)
        let oldRootPath = normalizedPath(oldRootURL)

        if path == oldRootPath {
            return newRootURL.standardizedFileURL
        }

        let oldRootPrefix = oldRootPath.hasSuffix("/") ? oldRootPath : "\(oldRootPath)/"
        guard path.hasPrefix(oldRootPrefix) else { return nil }

        let relativePath = String(path.dropFirst(oldRootPrefix.count))
        return newRootURL.appending(path: relativePath).standardizedFileURL
    }

    static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)

        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        return path
    }
}
