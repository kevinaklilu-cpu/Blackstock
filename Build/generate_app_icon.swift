#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let output = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)

try FileManager.default.createDirectory(
    at: output,
    withIntermediateDirectories: true
)

let variants: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(
            domain: "BlackstockIcon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Bitmap allocation failed"]
        )
    }

    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(
            domain: "BlackstockIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Graphics context failed"]
        )
    }
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let width = CGFloat(pixels) * 0.84
    let height = CGFloat(pixels) * 0.61
    let rect = NSRect(
        x: (CGFloat(pixels) - width) / 2,
        y: (CGFloat(pixels) - height) / 2,
        width: width,
        height: height
    )

    let red = NSColor(
        calibratedRed: 0.95,
        green: 0.04,
        blue: 0.16,
        alpha: 1
    )
    red.setFill()
    NSBezierPath(
        roundedRect: rect,
        xRadius: height * 0.24,
        yRadius: height * 0.24
    ).fill()

    let font = NSFont.systemFont(
        ofSize: height * 0.58,
        weight: .black
    )
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let letter = NSAttributedString(
        string: "B",
        attributes: attributes
    )
    let letterSize = letter.size()
    let point = NSPoint(
        x: rect.midX - letterSize.width / 2,
        y: rect.midY - letterSize.height / 2 + height * 0.035
    )
    letter.draw(at: point)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(
        using: .png,
        properties: [:]
    ) else {
        throw NSError(
            domain: "BlackstockIcon",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"]
        )
    }
    return png
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(
        to: output.appendingPathComponent(variant.filename),
        options: .atomic
    )
}
