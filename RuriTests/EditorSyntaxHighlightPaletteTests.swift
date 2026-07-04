//
//  EditorSyntaxHighlightPaletteTests.swift
//  ruriTests
//

import XCTest
@testable import ruri

// text → role → 色 の2段のうち後段(role → 色)を固定するテスト。前段(text → role)は
// SyntaxHighlightingServiceTests のスナップショットが固定する。
final class EditorSyntaxHighlightPaletteTests: XCTestCase {
    // SyntaxHighlightRole は CaseIterable ではないため、全13 role をここに列挙して網羅を固定する。
    // role が増減したらこの表とパレット両方の更新が必要になる。
    private static let expectedColors: [(role: SyntaxHighlightRole, light: UInt32, dark: UInt32)] = [
        (.keyword, 0xA626A4, 0xC678DD),
        (.type, 0xC18401, 0xE5C07B),
        (.string, 0x50A14F, 0x98C379),
        (.number, 0x986801, 0xD19A66),
        (.comment, 0x7F848E, 0x7F848E),
        (.function, 0x4078F2, 0x61AFEF),
        (.property, 0xE45649, 0xE06C75),
        (.operator, 0x383A42, 0xABB2BF),
        (.punctuation, 0x383A42, 0xABB2BF),
        (.tag, 0xE45649, 0xE06C75),
        (.attribute, 0x986801, 0xD19A66),
        (.constant, 0x0184BC, 0x56B6C2),
        (.variable, 0x383A42, 0xABB2BF)
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

    func testUnknownThemeNameFallsBackToLightPalette() throws {
        let color = SyntaxHighlightPalette.color(for: .keyword, themeName: "solarized")
        try assertColor(color, matchesHex: 0xA626A4, message: "unknown theme keyword")
    }

    func testThemeNameContainingDarkSelectsDarkPalette() throws {
        // テーマ判定は "dark" の部分文字列一致(実装仕様の固定)。
        let color = SyntaxHighlightPalette.color(for: .keyword, themeName: "my-dark-theme")
        try assertColor(color, matchesHex: 0xC678DD, message: "substring dark keyword")
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
