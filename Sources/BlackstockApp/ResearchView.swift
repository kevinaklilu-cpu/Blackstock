#if os(macOS)
import SwiftUI
import BlackstockCore

struct ResearchView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var trends: TrendViewModel
    @State private var selectedClusterID: String?

    private var clusters: [NicheCluster] { ResearchEngine().clusters(from: trends.items) }
    private var selectedCluster: NicheCluster? { clusters.first { $0.id == selectedClusterID } ?? clusters.first }

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(clusters) { cluster in
                        Button { selectedClusterID = cluster.id } label: {
                            BlackstockCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text(cluster.topic).font(.headline); Spacer(); Text("\(cluster.videoCount) Videos").font(.caption).foregroundStyle(.secondary) }
                                    Text("\(cluster.creatorCount) Creator · Median \(BlackstockFormat.compact(Int(cluster.medianViews))) Aufrufe · \(String(format: "%.0f", cluster.medianViewsPerHour)) Aufrufe/h").font(.caption).foregroundStyle(.secondary)
                                    HStack { Label("\(cluster.shortCount) Shorts", systemImage: "rectangle.portrait"); Label("\(cluster.longformCount) Longform", systemImage: "rectangle") }.font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(16)
            }.frame(minWidth: 380, idealWidth: 470)

            Group {
                if let cluster = selectedCluster {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(cluster.topic).font(.largeTitle.bold())
                            Text("Nischen-Radar aus den tatsächlich geladenen Videos. Keine erfundene Marktgröße; Blackstock zeigt nur beobachtbare Creator-, Reichweiten- und Geschwindigkeits-Signale.").foregroundStyle(.secondary)
                            HStack(spacing: 18) {
                                MetricLabel(value: "\(cluster.creatorCount)", label: "Creator")
                                MetricLabel(value: BlackstockFormat.compact(Int(cluster.medianViews)), label: "Median-Aufrufe")
                                MetricLabel(value: String(format: "%.0f/h", cluster.medianViewsPerHour), label: "Median-Dynamik")
                            }
                            HStack {
                                Button("In Trends untersuchen") { trends.query = cluster.topic; trends.search(apiKey: Keychain.read("youtube-data-api-key"), regionCode: app.regionCode, channel: app.channel); app.selection = .trends }.buttonStyle(.borderedProminent)
                                Button("Ideen daraus öffnen") { app.selection = .ideas }
                            }
                            Divider()
                            Text("Belege").font(.title2.bold())
                            ForEach(cluster.evidence) { signal in
                                Button { app.openTrend(signal) } label: {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: signal.video.thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }.frame(width: 136, height: 76).clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(signal.video.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                            Text("\(signal.video.channelTitle) · \(BlackstockFormat.compact(signal.video.viewCount)) Aufrufe · \(String(format: "%.0f/h", signal.video.viewsPerHour))").font(.caption).foregroundStyle(.secondary)
                                            if let reason = signal.reasons.first { Text(reason.label).font(.caption2).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }.padding(22)
                    }
                } else {
                    EmptyState(title: "Noch keine Nischencluster", systemImage: "scope", message: "Lade mehr Trenddaten oder suche nach einem Thema. Cluster entstehen erst, wenn mehrere echte Videos dasselbe Thema tragen.")
                }
            }.frame(minWidth: 540)
        }
        .navigationTitle("Recherche")
    }
}
#endif
