#if os(macOS)
import SwiftUI

struct BlackstockMark: View {
    var width: CGFloat = 44
    var height: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.26, style: .continuous)
                .fill(
                    Color(
                        red: 0.95,
                        green: 0.04,
                        blue: 0.16
                    )
                )

            Text("B")
                .font(
                    .system(
                        size: height * 0.58,
                        weight: .black,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)
                .offset(y: -0.4)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

struct BlackstockWordmark: View {
    var markWidth: CGFloat = 38
    var markHeight: CGFloat = 27
    var font: Font = .headline

    var body: some View {
        HStack(spacing: 9) {
            BlackstockMark(
                width: markWidth,
                height: markHeight
            )
            Text("Blackstock")
                .font(font.weight(.bold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Blackstock")
    }
}
#endif
