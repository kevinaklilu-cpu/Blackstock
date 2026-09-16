#if os(macOS)
import SwiftUI
import BlackstockCore
struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var trends: TrendViewModel
    let apiKey: String
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) { Text("Blackstock").font(.largeTitle.bold()); Text("Was jetzt relevant ist — und was du als Nächstes tun kannst.").font(.title3).foregroundStyle(.secondary) }
            if let error = trends.errorMessage, trends.items.isEmpty { BlackstockCard { VStack(alignment: .leading, spacing: 10) { Text("Live-Trends sind noch nicht verbunden").font(.headline); Text(error).foregroundStyle(.secondary); Button("Einstellungen öffnen") { app.selection = .settings } } } }
            else { HStack(spacing: 12) { summaryCard(title: "Aktuell relevant", value: "\(trends.items.count)", subtitle: "geladene Signale"); summaryCard(title: "Short-Potenzial", value: "\(trends.items.filter { $0.recommendedFormat == .short }.count)", subtitle: "für schnelle Produktion"); summaryCard(title: "Longform", value: "\(trends.items.filter { $0.recommendedFormat == .longform }.count)", subtitle: "Themen mit Tiefe") } }
            Text("Nächste Schritte").font(.title2.bold())
            ForEach(trends.items.prefix(6)) { trend in Button { app.openTrend(trend) } label: { HStack(spacing: 14) { AsyncImage(url: trend.video.thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }.frame(width: 150, height: 84).clipShape(RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 7) { Text(trend.video.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading); Text(trend.video.channelTitle).font(.subheadline).foregroundStyle(.secondary); if let reason = trend.reasons.first { Label(reason.label, systemImage: reason.strength.symbol).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Text(trend.recommendedFormat == .short ? "Short" : "Longform").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule()) }.padding(12).contentShape(Rectangle()) }.buttonStyle(.plain) }
        }.padding(24) }.task { if trends.items.isEmpty { trends.search(apiKey: apiKey, channel: app.channel) } }
    }
    private func summaryCard(title: String, value: String, subtitle: String) -> some View { BlackstockCard { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit(); Text(subtitle).font(.caption2).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity, alignment: .leading) } }
}
#endif
