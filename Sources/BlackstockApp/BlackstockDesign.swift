#if os(macOS)
import SwiftUI
import AppKit

enum BlackstockDesign {
    static let accent = Color(red: 0.94, green: 0.10, blue: 0.17)
    static let accentGlow = Color(red: 1.0, green: 0.30, blue: 0.20)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let raisedSurface = Color(nsColor: .textBackgroundColor)
    static let mediaSurface = Color.black
    static let subtleBorder = Color.primary.opacity(0.10)
    static let mutedFill = Color.primary.opacity(0.045)
    static let selectedFill = accent.opacity(0.11)
    static let selectedBorder = accent.opacity(0.38)
    static let cornerRadius: CGFloat = 14
}

private struct BlackstockSurfaceModifier: ViewModifier {
    let raised: Bool
    func body(content: Content) -> some View {
        content
            .background(
                raised
                    ? BlackstockDesign.raisedSurface
                    : BlackstockDesign.surface,
                in: RoundedRectangle(
                    cornerRadius: BlackstockDesign.cornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: BlackstockDesign.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(BlackstockDesign.subtleBorder)
            )
            .shadow(
                color: raised ? Color.black.opacity(0.10) : .clear,
                radius: raised ? 14 : 0,
                y: raised ? 5 : 0
            )
    }
}

extension View {
    func blackstockSurface(raised: Bool = false) -> some View {
        modifier(BlackstockSurfaceModifier(raised: raised))
    }
}
#endif
