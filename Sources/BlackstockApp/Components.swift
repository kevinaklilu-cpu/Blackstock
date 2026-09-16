#if os(macOS)
import SwiftUI
import WebKit
import AppKit
import BlackstockCore

extension Color {
    static let blackstockRed = Color(red: 1.0, green: 0.0, blue: 0.0)
    static let blackstockSurface = Color(nsColor: NSColor.windowBackgroundColor)
    static let blackstockSidebar = Color(nsColor: NSColor.controlBackgroundColor)
    static let blackstockPanel = Color.primary.opacity(0.038)
    static let blackstockBorder = Color.primary.opacity(0.075)
}

struct BlackstockBrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color.blackstockRed)
                .frame(width: size * 1.55, height: size)
                .shadow(color: Color.blackstockRed.opacity(0.24), radius: size * 0.16, y: size * 0.05)
            HStack(spacing: size * 0.10) {
                Text("B")
                    .font(.system(size: size * 0.50, weight: .black, design: .rounded))
                    .baselineOffset(size * 0.01)
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 1, height: size * 0.42)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.34, weight: .black))
                    .offset(x: size * 0.015)
            }
            .foregroundStyle(.white)
        }
        .frame(width: size * 1.55, height: size)
        .accessibilityLabel("Blackstock")
    }
}

struct BlackstockBrandLockup: View {
    var compact = false
    var body: some View {
        HStack(spacing: 11) {
            BlackstockBrandMark(size: 28)
            if !compact {
                Text("Blackstock")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .tracking(-0.35)
            }
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
            Circle().fill(
                LinearGradient(
                    colors: [Color.primary.opacity(0.15), Color.primary.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Text(initials).font(.system(size: size * 0.34, weight: .bold, design: .rounded))
        }
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .frame(width: size, height: size)
    }
}

struct BlackstockCard<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(hovered ? Color.primary.opacity(0.060) : Color.blackstockPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovered ? 0.12 : 0.075))
            )
            .shadow(color: .black.opacity(hovered ? 0.10 : 0.035), radius: hovered ? 18 : 7, y: hovered ? 8 : 2)
            .scaleEffect(hovered ? 1.003 : 1)
            .onHover { inside in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) { hovered = inside }
            }
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
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                if connected {
                    Circle()
                        .fill(Color.green.opacity(0.24))
                        .frame(width: pulse ? 13 : 8, height: pulse ? 13 : 8)
                }
                Circle().fill(connected ? Color.green : Color.secondary).frame(width: 7, height: 7)
            }
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .onAppear {
            guard connected else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct SidebarGroupLabel: View {
    let title: String
    let expanded: Bool
    var body: some View {
        Group {
            if expanded {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            } else {
                Divider().padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }
}

extension SignalStrength {
    var symbol: String {
        switch self { case .high: return "arrow.up.right"; case .medium: return "minus"; case .low: return "circle" }
    }
}
#endif
