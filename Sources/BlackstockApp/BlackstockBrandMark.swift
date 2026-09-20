#if os(macOS)
import SwiftUI

struct BlackstockBrandMark: View {
    var width: CGFloat = 44

    private var height: CGFloat {
        width * 0.68
    }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: width * 0.22,
                style: .continuous
            )
            .fill(Color(red: 1.0, green: 0.0, blue: 0.0))

            Text("B")
                .font(
                    .system(
                        size: width * 0.48,
                        weight: .black,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .offset(y: -width * 0.01)
        }
        .frame(width: width, height: height)
        .shadow(
            color: Color.black.opacity(0.14),
            radius: 1.5,
            y: 1
        )
        .accessibilityHidden(true)
    }
}
#endif
