#if os(macOS)
import AppKit

@MainActor
enum BrandAppIcon {
    static func make(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let outer = NSRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88)
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        NSBezierPath(roundedRect: outer, xRadius: size * 0.19, yRadius: size * 0.19).fill()

        let redRect = NSRect(x: size * 0.16, y: size * 0.29, width: size * 0.68, height: size * 0.42)
        NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSBezierPath(roundedRect: redRect, xRadius: size * 0.105, yRadius: size * 0.105).fill()

        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: size * 0.445, y: size * 0.395))
        triangle.line(to: NSPoint(x: size * 0.445, y: size * 0.605))
        triangle.line(to: NSPoint(x: size * 0.625, y: size * 0.5))
        triangle.close()
        NSColor.white.setFill()
        triangle.fill()
        return image
    }
}
#endif
