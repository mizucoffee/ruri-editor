#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSlot {
    let size: Int
    let scale: Int
    let filename: String

    var pixels: Int {
        size * scale
    }
}

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceIconURL = projectRoot
    .appendingPathComponent("Ruri/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let outputDirectoryURL = projectRoot
    .appendingPathComponent("Ruri/Assets.xcassets/DevAppIcon.appiconset")

let iconSlots = [
    IconSlot(size: 16, scale: 1, filename: "icon_16x16.png"),
    IconSlot(size: 16, scale: 2, filename: "icon_16x16@2x.png"),
    IconSlot(size: 32, scale: 1, filename: "icon_32x32.png"),
    IconSlot(size: 32, scale: 2, filename: "icon_32x32@2x.png"),
    IconSlot(size: 128, scale: 1, filename: "icon_128x128.png"),
    IconSlot(size: 128, scale: 2, filename: "icon_128x128@2x.png"),
    IconSlot(size: 256, scale: 1, filename: "icon_256x256.png"),
    IconSlot(size: 256, scale: 2, filename: "icon_256x256@2x.png"),
    IconSlot(size: 512, scale: 1, filename: "icon_512x512.png"),
    IconSlot(size: 512, scale: 2, filename: "icon_512x512@2x.png")
]

func loadPNG(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(
            domain: "GenerateDevAppIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to read source icon at \(url.path)"]
        )
    }

    return image
}

func makeDevIcon(sourceImage: CGImage, pixelSize: Int) throws -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(
            domain: "GenerateDevAppIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create drawing context for \(pixelSize)x\(pixelSize)"]
        )
    }

    let bounds = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
    context.interpolationQuality = .high
    context.draw(sourceImage, in: bounds)

    let badgeSize = max(8, Int(Double(pixelSize) * 0.34))
    let badgeInset = max(2, Int(Double(pixelSize) * 0.055))
    let badgeCornerRadius = max(3, Double(badgeSize) * 0.23)
    let badgeRect = CGRect(
        x: pixelSize - badgeInset - badgeSize,
        y: badgeInset,
        width: badgeSize,
        height: badgeSize
    )

    context.saveGState()
    let badgePath = CGPath(
        roundedRect: badgeRect,
        cornerWidth: badgeCornerRadius,
        cornerHeight: badgeCornerRadius,
        transform: nil
    )
    context.setShadow(
        offset: CGSize(width: 0, height: -Double(pixelSize) * 0.012),
        blur: Double(pixelSize) * 0.025,
        color: NSColor.black.withAlphaComponent(0.32).cgColor
    )
    context.setFillColor(NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.10, alpha: 1.0).cgColor)
    context.addPath(badgePath)
    context.fillPath()
    context.restoreGState()

    context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    context.setLineWidth(max(1, Double(pixelSize) * 0.012))
    context.addPath(badgePath)
    context.strokePath()

    if pixelSize >= 64 {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let fontSize = Double(pixelSize) * 0.095
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .black),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
            .paragraphStyle: paragraphStyle
        ]
        let text = "DEV" as NSString
        let textHeight = fontSize * 1.18
        let textRect = CGRect(
            x: badgeRect.minX,
            y: badgeRect.midY - textHeight / 2.0 + fontSize * 0.06,
            width: badgeRect.width,
            height: textHeight
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(in: textRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    } else {
        let dotInset = Double(badgeSize) * 0.28
        context.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor)
        context.fillEllipse(in: badgeRect.insetBy(dx: dotInset, dy: dotInset))
    }

    guard let image = context.makeImage() else {
        throw NSError(
            domain: "GenerateDevAppIcon",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Failed to render \(pixelSize)x\(pixelSize) icon"]
        )
    }

    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(
            domain: "GenerateDevAppIcon",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination at \(url.path)"]
        )
    }

    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(
            domain: "GenerateDevAppIcon",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG at \(url.path)"]
        )
    }
}

func writeContentsJSON() throws {
    let images = iconSlots.map { slot -> [String: String] in
        [
            "filename": slot.filename,
            "idiom": "mac",
            "scale": "\(slot.scale)x",
            "size": "\(slot.size)x\(slot.size)"
        ]
    }
    let contents: [String: Any] = [
        "images": images,
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: outputDirectoryURL.appendingPathComponent("Contents.json"))
}

try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

let sourceImage = try loadPNG(at: sourceIconURL)
for slot in iconSlots {
    let image = try makeDevIcon(sourceImage: sourceImage, pixelSize: slot.pixels)
    try writePNG(image, to: outputDirectoryURL.appendingPathComponent(slot.filename))
}
try writeContentsJSON()

print("Generated \(iconSlots.count) development app icons in \(outputDirectoryURL.path)")
