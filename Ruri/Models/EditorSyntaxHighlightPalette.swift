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

    // IntelliJ Light / IntelliJ (New UI) Dark 準拠。IntelliJ が色付けしない type / variable /
    // operator / punctuation は意図的に省略し、.labelColor フォールバックに落とす。
    private static let lightColors: [SyntaxHighlightRole: NSColor] = [
        .keyword: color(0x00, 0x33, 0xB3),
        .string: color(0x06, 0x7D, 0x17),
        .number: color(0x17, 0x50, 0xEB),
        .comment: color(0x8C, 0x8C, 0x8C),
        .function: color(0x00, 0x62, 0x7A),
        .property: color(0x87, 0x10, 0x94),
        .tag: color(0x00, 0x33, 0xB3),
        .attribute: color(0x17, 0x4A, 0xD4),
        .annotation: color(0x9E, 0x88, 0x0D),
        .constant: color(0x87, 0x10, 0x94)
    ]

    private static let darkColors: [SyntaxHighlightRole: NSColor] = [
        .keyword: color(0xCF, 0x8E, 0x6D),
        .string: color(0x6A, 0xAB, 0x73),
        .number: color(0x2A, 0xAC, 0xB8),
        .comment: color(0x7A, 0x7E, 0x85),
        .function: color(0x56, 0xA8, 0xF5),
        .property: color(0xC7, 0x7D, 0xBB),
        .tag: color(0xD5, 0xB7, 0x78),
        .attribute: color(0xBD, 0xBD, 0xBD),
        .annotation: color(0xB3, 0xAE, 0x60),
        .constant: color(0xC7, 0x7D, 0xBB)
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
