//
//  EditorSyntaxHighlightPaletteTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

// text → role → 色 の2段のうち後段(role → 色)を固定するテスト。前段(text → role)は
// SyntaxHighlightingServiceTests のスナップショットが固定する。
final class EditorSyntaxHighlightPaletteTests: XCTestCase {
    // SyntaxHighlightRole は CaseIterable ではないため、全14 role をこの2表に列挙して網羅を固定する。
    // role が増減したらこの表とパレット両方の更新が必要になる。
    // 配色は IntelliJ Light (light) / IntelliJ New UI Dark (dark) 準拠。
    private static let expectedColors: [(role: SyntaxHighlightRole, light: UInt32, dark: UInt32)] = [
        (.keyword, 0x0033B3, 0xCF8E6D),
        (.string, 0x067D17, 0x6AAB73),
        (.number, 0x1750EB, 0x2AACB8),
        (.comment, 0x8C8C8C, 0x7A7E85),
        (.function, 0x00627A, 0x56A8F5),
        (.property, 0x871094, 0xC77DBB),
        (.tag, 0x0033B3, 0xD5B778),
        (.attribute, 0x174AD4, 0xBDBDBD),
        (.annotation, 0x9E880D, 0xB3AE60),
        (.constant, 0x871094, 0xC77DBB)
    ]

    // IntelliJ が色付けしない role。パレットに定義されず .labelColor に落ちる。
    private static let defaultColorRoles: [SyntaxHighlightRole] = [
        .type,
        .variable,
        .operator,
        .punctuation
    ]

    // MARK: - color(for:themeName:)

    func testLightThemeColorsMatchPaletteForAllRoles() throws {
        for expected in Self.expectedColors {
            let color = SyntaxHighlightPalette.color(for: expected.role, themeName: "tree-sitter-light")
            try assertColor(color, matchesHex: expected.light, message: "light \(expected.role.rawValue)")
        }
    }

    func testDarkThemeColorsMatchPaletteForAllRoles() throws {
        for expected in Self.expectedColors {
            let color = SyntaxHighlightPalette.color(for: expected.role, themeName: "tree-sitter-dark")
            try assertColor(color, matchesHex: expected.dark, message: "dark \(expected.role.rawValue)")
        }
    }

    func testDefaultColorRolesFallBackToLabelColorInBothThemes() {
        for role in Self.defaultColorRoles {
            for themeName in ["tree-sitter-light", "tree-sitter-dark"] {
                let color = SyntaxHighlightPalette.color(for: role, themeName: themeName)
                XCTAssertEqual(color, .labelColor, "\(themeName) \(role.rawValue)")
            }
        }
    }

    func testUnknownThemeNameFallsBackToLightPalette() throws {
        let color = SyntaxHighlightPalette.color(for: .keyword, themeName: "solarized")
        try assertColor(color, matchesHex: 0x0033B3, message: "unknown theme keyword")
    }

    func testThemeNameContainingDarkSelectsDarkPalette() throws {
        // テーマ判定は "dark" の部分文字列一致(実装仕様の固定)。
        let color = SyntaxHighlightPalette.color(for: .keyword, themeName: "my-dark-theme")
        try assertColor(color, matchesHex: 0xCF8E6D, message: "substring dark keyword")
    }

    // MARK: - SyntaxHighlightingService.themeName(for:)

    func testThemeNameForAquaAppearanceIsLight() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        XCTAssertEqual(SyntaxHighlightingService.themeName(for: appearance), "tree-sitter-light")
    }

    func testThemeNameForDarkAquaAppearanceIsDark() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        XCTAssertEqual(SyntaxHighlightingService.themeName(for: appearance), "tree-sitter-dark")
    }

    // MARK: - Helpers

    private func assertColor(
        _ color: NSColor,
        matchesHex hex: UInt32,
        message: String,
        file: StaticString = #filePath,
        line: UInt = 0
    ) throws {
        let rgb = try XCTUnwrap(color.usingColorSpace(.genericRGB), message, file: file, line: line)
        let accuracy: CGFloat = 0.5 / 255
        XCTAssertEqual(rgb.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: accuracy, message)
        XCTAssertEqual(rgb.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: accuracy, message)
        XCTAssertEqual(rgb.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: accuracy, message)
        XCTAssertEqual(rgb.alphaComponent, 1, message)
    }
}
