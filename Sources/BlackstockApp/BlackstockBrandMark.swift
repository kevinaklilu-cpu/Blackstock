#if os(macOS)
import SwiftUI

struct BlackstockBrandMark: View {
    var width: CGFloat = 44

    private var height: CGFloat {
        width * 0.62
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.18, style: .continuous)
                .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
            Text("B")
                .font(.system(size: width * 0.48, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: -width * 0.015)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}
#endif
