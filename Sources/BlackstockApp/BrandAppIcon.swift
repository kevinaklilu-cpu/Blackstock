#if os(macOS)
import AppKit

@MainActor
enum BrandAppIcon {
    static func make(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let outer = NSRect(x: size * 0.055, y: size * 0.055, width: size * 0.89, height: size * 0.89)
        NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
        NSBezierPath(roundedRect: outer, xRadius: size * 0.205, yRadius: size * 0.205).fill()

        let badge = NSRect(x: size * 0.13, y: size * 0.30, width: size * 0.74, height: size * 0.40)
        NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSBezierPath(roundedRect: badge, xRadius: size * 0.105, yRadius: size * 0.105).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let bRect = NSRect(x: size * 0.205, y: size * 0.337, width: size * 0.245, height: size * 0.315)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.235, weight: .black),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        ("B" as NSString).draw(in: bRect, withAttributes: attrs)

        NSColor(calibratedWhite: 1, alpha: 0.32).setFill()
        NSBezierPath(rect: NSRect(x: size * 0.49, y: size * 0.385, width: size * 0.006, height: size * 0.23)).fill()

        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: size * 0.575, y: size * 0.395))
        triangle.line(to: NSPoint(x: size * 0.575, y: size * 0.605))
        triangle.line(to: NSPoint(x: size * 0.755, y: size * 0.5))
        triangle.close()
        NSColor.white.setFill()
        triangle.fill()
        return image
    }
}
#endif
