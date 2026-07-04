//
//  SearchResultPathPolicy.swift
//  ruri
//

import Foundation

// 検索・usage結果の相対パス文字列を「testディレクトリ配下か」で分類するポリシー。相対パスの計算は
// 各呼び出し元が FileURLRewriter 経由で済ませている前提で、本型は文字列の解釈だけを担う。
// パスの表示整形（FileTreeView の FileTreePathFormatter）とは役割が別であり、統合しない。
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
