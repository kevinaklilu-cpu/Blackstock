#if os(macOS)
import SwiftUI
import WebKit
import AppKit
import BlackstockCore

extension Color {
    static let blackstockRed = Color(red: 1.0, green: 0.0, blue: 0.0)
    static let blackstockSurface = Color(nsColor: NSColor.windowBackgroundColor)
    static let blackstockSidebar = Color(nsColor: NSColor.controlBackgroundColor)
}

struct BlackstockBrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.blackstockRed)
                .frame(width: size * 1.42, height: size)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .accessibilityLabel("Blackstock")
    }
}

struct BlackstockBrandLockup: View {
    var compact = false
    var body: some View {
        HStack(spacing: 11) {
            BlackstockBrandMark(size: 28)
            if !compact { Text("Blackstock").font(.system(size: 21, weight: .bold, design: .rounded)) }
        }
    }
}

struct ChannelAvatar: View {
    let title: String
    var size: CGFloat = 34
    private var initials: String {
        let parts = title.split(separator: " ").prefix(2)
        let value = parts.compactMap { $0.first }.map(String.init).joined()
        return value.isEmpty ? "B" : value.uppercased()
    }
    var body: some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.10))
            Text(initials).font(.system(size: size * 0.34, weight: .bold, design: .rounded))
        }.frame(width: size, height: size)
    }
}

struct BlackstockCard<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.055) : Color.primary.opacity(0.032))
            )
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(hovered ? 0.11 : 0.07)))
            .shadow(color: .black.opacity(hovered ? 0.09 : 0.035), radius: hovered ? 16 : 6, y: hovered ? 7 : 2)
            .scaleEffect(hovered ? 1.002 : 1)
            .onHover { inside in withAnimation(.easeOut(duration: 0.14)) { hovered = inside } }
    }
}

struct EmptyState: View {
    let title: String
    let systemImage: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.055)).frame(width: 74, height: 74)
                Image(systemName: systemImage).font(.system(size: 31, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(title).font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct YouTubePlayer: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?autoplay=0&rel=0") else { return }
        if webView.url != url { webView.load(URLRequest(url: url)) }
    }
}

struct MetricLabel: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LiveStatusPill: View {
    let text: String
    var connected = true
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

extension SignalStrength {
    var symbol: String {
        switch self { case .high: return "arrow.up.right"; case .medium: return "minus"; case .low: return "circle" }
    }
}
#endif
