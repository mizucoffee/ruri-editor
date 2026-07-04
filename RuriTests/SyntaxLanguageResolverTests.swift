//
//  SyntaxLanguageResolverTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

// AGENTS.md の11言語色分け検証の前段: 拡張子 → languageName の解決を固定する。
// 特に .gradle → "groovy"、.jsonl → "json" の正規化は、SyntaxHighlightingServiceTests が
// Gradle/JSONL 風サンプルを "groovy"/"json" として検証している前提そのもの。
final class SyntaxLanguageResolverTests: XCTestCase {
    func testExtensionsForElevenVerifiedLanguageGroupsResolveToWorkerLanguageNames() {
        let expectations: [(fileName: String, languageName: String)] = [
            ("Main.java", "java"),
            ("app.js", "javascript"),
            ("Main.kt", "kotlin"),
            ("build.groovy", "groovy"),
            ("build.gradle", "groovy"),
            ("app.ts", "typescript"),
            ("config.json", "json"),
            ("events.jsonl", "json"),
            ("README.md", "markdown"),
            ("config.yaml", "yaml"),
            ("config.yml", "yaml"),
            ("style.css", "css"),
            ("index.html", "html"),
            ("config.xml", "xml")
        ]
        for expectation in expectations {
            let url = URL(fileURLWithPath: "/tmp/\(expectation.fileName)")
            XCTAssertEqual(
                SyntaxLanguageResolver.languageName(for: url),
                expectation.languageName,
                expectation.fileName
            )
        }
    }
}
