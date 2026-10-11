#if os(macOS)
import SwiftUI

struct BlackstockBrandMark: View {
    var width: CGFloat = 44

    private var height: CGFloat {
        width * 0.70
    }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: width * 0.24,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        BlackstockDesign.accentGlow,
                        BlackstockDesign.accent
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            RoundedRectangle(
                cornerRadius: width * 0.24,
                style: .continuous
            )
            .strokeBorder(
                Color.white.opacity(0.12),
                lineWidth: max(width * 0.025, 1)
            )

            Text("B")
                .font(
                    .system(
                        size: width * 0.53,
                        weight: .black
                    )
                )
                .foregroundStyle(.white)

        }
        .frame(width: width, height: height)
        .shadow(
            color: BlackstockDesign.accent.opacity(0.24),
            radius: width * 0.16,
            y: width * 0.08
        )
        .accessibilityHidden(true)
    }
}
#endif
