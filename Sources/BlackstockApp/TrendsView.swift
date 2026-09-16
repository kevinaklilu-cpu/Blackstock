#if os(macOS)
import SwiftUI
import AppKit
import Foundation
import BlackstockCore

struct TrendsView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var model: TrendViewModel
    let apiKey: String
    @State private var selected: TrendSignal?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                controls
                Divider()
                if model.visibleItems.isEmpty && model.isLoading { ProgressView("Trends werden geladen …").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if model.visibleItems.isEmpty { EmptyState(title: "Keine Trends geladen", systemImage: "waveform.path.ecg", message: model.errorMessage ?? "Suche nach einem Thema oder passe die Filter an.") }
                else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.visibleItems) { item in trendRow(item).onAppear { model.loadMoreIfNeeded(current: item, apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) } }
                            if model.isLoading { ProgressView().padding() }
                        }.padding(12)
                    }
                }
            }.frame(minWidth: 440, idealWidth: 590)
            detail(selected ?? app.activeTrend ?? model.visibleItems.first).frame(minWidth: 500)
        }
        .navigationTitle("Trends")
        .onChange(of: app.activeTrend) { value in selected = value }
        .task { if model.items.isEmpty { model.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) } }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Thema oder Nische — leer = YouTube aktuell", text: $model.query).textFieldStyle(.roundedBorder).onSubmit { model.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) }
                Button("Suchen") { model.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) }.keyboardShortcut(.return, modifiers: [.command])
            }
            HStack {
                Picker("Format", selection: $model.selectedFormat) { Text("Alle Formate").tag(VideoFormat?.none); Text("Short").tag(VideoFormat?.some(.short)); Text("Longform").tag(VideoFormat?.some(.longform)) }.labelsHidden().frame(width: 220)
                Picker("Dauer", selection: $model.durationFilter) {
                    Text("Alle Längen").tag(VideoDurationFilter.all); Text("< 1 Min").tag(VideoDurationFilter.upToOne); Text("1–4 Min").tag(VideoDurationFilter.oneToFour); Text("4–10 Min").tag(VideoDurationFilter.fourToTen); Text("10–20 Min").tag(VideoDurationFilter.tenToTwenty); Text("20–60 Min").tag(VideoDurationFilter.twentyToSixty); Text("60+ Min").tag(VideoDurationFilter.overSixty)
                }.labelsHidden().frame(width: 170)
                Spacer()
                if !app.regionCode.isEmpty { Text(app.regionCode.uppercased()).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(.quaternary, in: Capsule()) }
            }
        }.padding(12)
    }

    private func trendRow(_ item: TrendSignal) -> some View {
        Button { selected = item; app.activeTrend = item } label: {
            HStack(spacing: 12) {
                AsyncImage(url: item.video.thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }.frame(width: 132, height: 74).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.video.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    HStack { Text(item.video.channelTitle); Text("•"); Text("\(BlackstockFormat.compact(item.video.viewCount)) Aufrufe"); Text("•"); Text(BlackstockFormat.duration(item.video.durationSeconds)) }.font(.caption).foregroundStyle(.secondary)
                    if let reason = item.reasons.first { Text(reason.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
            }.padding(8).background((selected?.id == item.id) ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func detail(_ item: TrendSignal?) -> some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    YouTubePlayer(videoID: item.video.id).frame(minHeight: 300).clipShape(RoundedRectangle(cornerRadius: 14))
                    Text(item.video.title).font(.title2.bold())
                    HStack(spacing: 24) { MetricLabel(value: BlackstockFormat.compact(item.video.viewCount), label: "Aufrufe"); MetricLabel(value: String(format: "%.0f/h", item.video.viewsPerHour), label: "aktuelle Geschwindigkeit"); MetricLabel(value: BlackstockFormat.duration(item.video.durationSeconds), label: "Dauer") }
                    VStack(alignment: .leading, spacing: 8) { Text("Warum relevant?").font(.headline); ForEach(item.reasons) { reason in Label(reason.label, systemImage: reason.strength.symbol) } }
                    HStack { Button("Projekt starten") { app.startProject(from: item) }.buttonStyle(.borderedProminent); Button("Clip / Remix auf YouTube") { openYouTube(item.video.id) }; Menu("Mehr") { Button("Video auf YouTube öffnen") { openYouTube(item.video.id) }; Button("Video-ID kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.video.id, forType: .string) } } }
                }.padding(20)
            }
        } else { EmptyState(title: "Trend auswählen", systemImage: "play.rectangle") }
    }

    private func openYouTube(_ id: String) { guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }; NSWorkspace.shared.open(url) }
}
#endif
