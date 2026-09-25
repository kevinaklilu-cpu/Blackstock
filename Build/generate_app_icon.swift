#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift OUTPUT_ICNS\n", stderr)
    exit(2)
}

let fm = FileManager.default
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let work = fm.temporaryDirectory.appendingPathComponent("BlackstockIcon-\(UUID().uuidString).iconset", isDirectory: true)
try fm.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }

func render(size: Int, scale: Int, name: String) throws {
    let pixels = size * scale
    guard let rep = NSBitmapImageRep(
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
    ) else { throw NSError(domain: "BlackstockIcon", code: 1) }

    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw NSError(domain: "BlackstockIcon", code: 2)
    }
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let rect = NSRect(
        x: CGFloat(size) * 0.085,
        y: CGFloat(size) * 0.215,
        width: CGFloat(size) * 0.83,
        height: CGFloat(size) * 0.58
    )
    let path = NSBezierPath(
        roundedRect: rect,
        xRadius: CGFloat(size) * 0.145,
        yRadius: CGFloat(size) * 0.145
    )
    NSColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
    path.fill()

    let font = NSFont.systemFont(
        ofSize: CGFloat(size) * 0.35,
        weight: .heavy
    )
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let mark = NSString(string: "B")
    let markSize = mark.size(withAttributes: attrs)
    mark.draw(
        at: NSPoint(
            x: (CGFloat(size) - markSize.width) / 2,
            y: (CGFloat(size) - markSize.height) / 2
        ),
        withAttributes: attrs
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BlackstockIcon", code: 3)
    }
    try data.write(to: work.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    try render(size: size, scale: 1, name: "icon_\(size)x\(size).png")
    try render(size: size, scale: 2, name: "icon_\(size)x\(size)@2x.png")
}

// Write the PNG-backed ICNS container directly. This avoids an iconutil
// regression on recent macOS toolchains that rejects otherwise valid iconsets.
let chunks: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_128x128@2x.png"),
    ("ic09", "icon_256x256@2x.png"),
    ("ic10", "icon_512x512@2x.png"),
]

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

var body = Data()
for (type, fileName) in chunks {
    let png = try Data(contentsOf: work.appendingPathComponent(fileName))
    body.append(contentsOf: type.utf8)
    appendUInt32(UInt32(png.count + 8), to: &body)
    body.append(png)
}

var icns = Data("icns".utf8)
appendUInt32(UInt32(body.count + 8), to: &icns)
icns.append(body)
try icns.write(to: output, options: .atomic)
