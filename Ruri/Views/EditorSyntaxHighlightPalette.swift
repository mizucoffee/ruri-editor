//
//  EditorSyntaxHighlightPalette.swift
//  ruri
//

import AppKit

enum SyntaxHighlightPalette {
    static func color(for role: SyntaxHighlightRole, themeName: String) -> NSColor {
        let palette = themeName.contains("dark") ? darkColors : lightColors
        return palette[role] ?? .labelColor
    }

    private static let lightColors: [SyntaxHighlightRole: NSColor] = [
        .keyword: color(0xA6, 0x26, 0xA4),
        .type: color(0xC1, 0x84, 0x01),
        .string: color(0x50, 0xA1, 0x4F),
        .number: color(0x98, 0x68, 0x01),
        .comment: color(0x7F, 0x84, 0x8E),
        .function: color(0x40, 0x78, 0xF2),
        .property: color(0xE4, 0x56, 0x49),
        .operator: color(0x38, 0x3A, 0x42),
        .punctuation: color(0x38, 0x3A, 0x42),
        .tag: color(0xE4, 0x56, 0x49),
        .attribute: color(0x98, 0x68, 0x01),
        .constant: color(0x01, 0x84, 0xBC),
        .variable: color(0x38, 0x3A, 0x42)
    ]

    private static let darkColors: [SyntaxHighlightRole: NSColor] = [
        .keyword: color(0xC6, 0x78, 0xDD),
        .type: color(0xE5, 0xC0, 0x7B),
        .string: color(0x98, 0xC3, 0x79),
        .number: color(0xD1, 0x9A, 0x66),
        .comment: color(0x7F, 0x84, 0x8E),
        .function: color(0x61, 0xAF, 0xEF),
        .property: color(0xE0, 0x6C, 0x75),
        .operator: color(0xAB, 0xB2, 0xBF),
        .punctuation: color(0xAB, 0xB2, 0xBF),
        .tag: color(0xE0, 0x6C, 0x75),
        .attribute: color(0xD1, 0x9A, 0x66),
        .constant: color(0x56, 0xB6, 0xC2),
        .variable: color(0xAB, 0xB2, 0xBF)
    ]

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(
            calibratedRed: red / 255,
            green: green / 255,
            blue: blue / 255,
            alpha: 1
        )
    }
}
