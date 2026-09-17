#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct AnalyticsView: View {
    @EnvironmentObject private var app: AppState
    @State private var dataset: AnalyticsDataset?
    @State private var importing = false
    @State private var isLoadingLive = false
    @State private var errorMessage: String?
    @State private var sourceLabel = ""

    private var canLoadLive: Bool {
        app.channel.id != "local" && GoogleYouTubeAuth.isAuthenticated(channelID: app.channel.id)
    }
    private var sortedRows: [AnalyticsRow] { (dataset?.rows ?? []).sorted { $0.views > $1.views } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                analyticsHeader
                if let dataset {
                    kpiGrid(dataset)
                    performancePanel
                    contentTable
                } else {
                    emptyAnalytics
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                        .padding(12)
                        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .background(Color.blackstockSurface)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): importCSV(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .task(id: app.channel.id) {
            if canLoadLive { await loadLive() }
        }
    }

    private var analyticsHeader: some View {
        HStack(spacing: 16) {
            ChannelAvatar(title: app.channel.title, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("Channel Analytics").font(.largeTitle.bold())
                HStack(spacing: 6) {
                    Text(app.channel.title).font(.subheadline.weight(.semibold))
                    if !sourceLabel.isEmpty { Text("•"); Text(sourceLabel) }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingLive { ProgressView().controlSize(.small) }
            if canLoadLive {
                Button { Task { await loadLive() } } label: { Label("Live aktualisieren", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderedProminent).tint(.blackstockRed).disabled(isLoadingLive)
            }
            Button { importing = true } label: { Label("CSV importieren", systemImage: "square.and.arrow.down") }
                .buttonStyle(.bordered)
        }
    }

    private func kpiGrid(_ dataset: AnalyticsDataset) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            metricTile("Aufrufe", value: BlackstockFormat.compact(dataset.views), icon: "play.circle.fill", detail: sourceLabel)
            metricTile("Wiedergabezeit", value: String(format: "%.1f h", dataset.watchTimeHours), icon: "clock.fill", detail: "Gesamt")
            if dataset.impressions > 0 {
                metricTile("Impressionen", value: BlackstockFormat.compact(dataset.impressions), icon: "eye.fill", detail: "Thumbnail-Reichweite")
            }
            if let ctr = dataset.weightedCTR {
                metricTile("CTR", value: String(format: "%.1f %%", ctr * 100), icon: "cursorarrow.click.2", detail: "Gewichtet")
            }
            metricTile("Videos", value: "\(dataset.rows.count)", icon: "rectangle.stack.fill", detail: "Im Datensatz")
        }
    }

    private func metricTile(_ title: String, value: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.blackstockRed.opacity(0.10)).frame(width: 34, height: 34)
                    Image(systemName: icon).foregroundStyle(Color.blackstockRed)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .padding(15)
        .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))
    }

    private var performancePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance-Verteilung").font(.title3.bold())
                    Text("Top-Inhalte nach Aufrufen").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Top \(min(sortedRows.count, 12))").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.primary.opacity(0.055), in: Capsule())
            }
            if sortedRows.isEmpty {
                Text("Noch keine Videozeilen vorhanden.").font(.caption).foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    let rows = Array(sortedRows.prefix(12))
                    let maxViews = max(rows.map(\.views).max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 7) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(index == 0 ? Color.blackstockRed : Color.primary.opacity(0.15))
                                    .frame(height: max(10, (proxy.size.height - 26) * CGFloat(Double(row.views) / Double(maxViews))))
                                Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(16)
        .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.blackstockBorder))
    }

    private var contentTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content Performance").font(.title3.bold())
                Spacer()
                Text("\(sortedRows.count) Videos").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("#").frame(width: 28, alignment: .leading)
                    Text("Video").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Aufrufe").frame(width: 90, alignment: .trailing)
                    Text("Watchtime").frame(width: 100, alignment: .trailing)
                    if (dataset?.impressions ?? 0) > 0 { Text("Impressionen").frame(width: 105, alignment: .trailing) }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 9)
                Divider()
                ForEach(Array(sortedRows.prefix(100).enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 28, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let ctr = row.clickThroughRate { Text(String(format: "%.1f %% CTR", ctr * 100)).font(.caption2).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(BlackstockFormat.compact(row.views)).font(.subheadline.monospacedDigit()).frame(width: 90, alignment: .trailing)
                        Text(String(format: "%.1f h", row.watchTimeHours)).font(.subheadline.monospacedDigit()).frame(width: 100, alignment: .trailing)
                        if (dataset?.impressions ?? 0) > 0 { Text(BlackstockFormat.compact(row.impressions)).font(.subheadline.monospacedDigit()).frame(width: 105, alignment: .trailing) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.018) : Color.clear)
                    if index < min(sortedRows.count, 100) - 1 { Divider().opacity(0.65) }
                }
            }
            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))
        }
    }

    private var emptyAnalytics: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.blackstockRed.opacity(0.08)).frame(width: 92, height: 92)
                Image(systemName: "chart.xyaxis.line").font(.system(size: 38, weight: .medium)).foregroundStyle(Color.blackstockRed)
            }
            VStack(spacing: 6) {
                Text(canLoadLive ? "Kanaldaten laden" : "YouTube-Kanal verbinden").font(.title2.bold())
                Text(canLoadLive ? "Blackstock kann die letzten 28 Tage direkt aus YouTube Analytics laden. Alternativ kannst du weiterhin einen Studio-CSV-Export importieren." : "Verbinde einen YouTube-Kanal, damit Analytics automatisch im richtigen Creator-Workspace landet. CSV-Import bleibt zusätzlich verfügbar.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 560)
            }
            HStack(spacing: 10) {
                if canLoadLive {
                    Button { Task { await loadLive() } } label: { Label("Letzte 28 Tage laden", systemImage: "bolt.fill") }
                        .buttonStyle(.borderedProminent).tint(.blackstockRed)
                } else {
                    Button("Account verbinden") { app.showOnboardingAgain() }.buttonStyle(.borderedProminent).tint(.blackstockRed)
                }
                Button("CSV importieren") { importing = true }.buttonStyle(.bordered)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity)
        .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.blackstockBorder))
    }

    @MainActor
    private func loadLive() async {
        guard canLoadLive else { return }
        isLoadingLive = true
        errorMessage = nil
        do {
            dataset = try await YouTubeAnalyticsService().load(channelID: app.channel.id, days: 28)
            sourceLabel = "Live · letzte 28 Tage"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingLive = false
    }

    private func importCSV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            dataset = try AnalyticsCSVParser().parse(text)
            sourceLabel = "YouTube Studio CSV"
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
