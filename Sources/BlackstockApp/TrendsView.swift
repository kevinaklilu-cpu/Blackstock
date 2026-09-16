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
                discoverHeader
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                if model.visibleItems.isEmpty && model.isLoading {
                    VStack(spacing: 12) { ProgressView(); Text("YouTube-Signale werden geladen …").font(.caption).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.visibleItems.isEmpty {
                    EmptyState(title: "Keine Trends geladen", systemImage: "waveform.path.ecg", message: model.errorMessage ?? "Suche nach einem Thema oder passe die Filter an.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(model.visibleItems) { item in
                                TrendBrowseRow(item: item, selected: (selected ?? app.activeTrend)?.id == item.id) {
                                    withAnimation(.easeInOut(duration: 0.14)) { selected = item; app.activeTrend = item }
                                }
                                .onAppear { model.loadMoreIfNeeded(current: item, apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) }
                            }
                            if model.isLoading { ProgressView().padding(18) }
                        }
                        .padding(10)
                    }
                }
            }
            .frame(minWidth: 470, idealWidth: 610)

            detail(selected ?? app.activeTrend ?? model.visibleItems.first)
                .frame(minWidth: 520)
                .background(Color.primary.opacity(0.012))
        }
        .onChange(of: app.activeTrend) { value in selected = value }
        .task { if model.items.isEmpty { model.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) } }
    }

    private var discoverHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trends").font(.title2.bold())
                    Text(app.channel.id == "local" ? "YouTube entdecken" : "Für \(app.channel.title) eingeordnet")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !app.regionCode.isEmpty {
                    Text(app.regionCode.uppercased()).font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Thema oder Nische — leer = aktuell", text: $model.query)
                    .textFieldStyle(.plain)
                    .onSubmit { model.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) }
                Button { model.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) } label: {
                    Image(systemName: "arrow.right").font(.caption.weight(.bold)).frame(width: 27, height: 27)
                }
                .buttonStyle(.plain).background(Color.blackstockRed, in: Circle()).foregroundStyle(.white)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filterMenu(title: formatTitle, icon: "rectangle.on.rectangle") {
                        Button("Alle Formate") { model.selectedFormat = nil }
                        Button("Shorts") { model.selectedFormat = .short }
                        Button("Longform") { model.selectedFormat = .longform }
                    }
                    filterMenu(title: durationTitle, icon: "clock") {
                        Button("Alle Längen") { model.durationFilter = .all }
                        Button("< 1 Min") { model.durationFilter = .upToOne }
                        Button("1–4 Min") { model.durationFilter = .oneToFour }
                        Button("4–10 Min") { model.durationFilter = .fourToTen }
                        Button("10–20 Min") { model.durationFilter = .tenToTwenty }
                        Button("20–60 Min") { model.durationFilter = .twentyToSixty }
                        Button("60+ Min") { model.durationFilter = .overSixty }
                    }
                    if model.selectedFormat != nil || model.durationFilter != .all {
                        Button("Filter zurücksetzen") { model.selectedFormat = nil; model.durationFilter = .all }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                    }
                    Spacer()
                    Text("\(model.visibleItems.count) Videos").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
    }

    private func filterMenu<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: {
            HStack(spacing: 6) { Image(systemName: icon); Text(title); Image(systemName: "chevron.down").font(.caption2) }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.065)))
        }
        .menuStyle(.borderlessButton)
    }

    private var formatTitle: String {
        switch model.selectedFormat { case .short: return "Shorts"; case .longform: return "Longform"; case nil: return "Alle Formate" }
    }

    private var durationTitle: String {
        switch model.durationFilter {
        case .all: return "Alle Längen"
        case .upToOne: return "< 1 Min"
        case .oneToFour: return "1–4 Min"
        case .fourToTen: return "4–10 Min"
        case .tenToTwenty: return "10–20 Min"
        case .twentyToSixty: return "20–60 Min"
        case .overSixty: return "60+ Min"
        }
    }

    @ViewBuilder private func detail(_ item: TrendSignal?) -> some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack(alignment: .topTrailing) {
                        YouTubePlayer(videoID: item.video.id)
                            .frame(minHeight: 315)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                        Text(item.recommendedFormat == .short ? "SHORT-CHANCE" : "LONGFORM")
                            .font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Color.blackstockRed.opacity(0.92), in: Capsule()).padding(12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.video.title).font(.system(size: 24, weight: .bold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 9) {
                            ChannelAvatar(title: item.video.channelTitle, size: 28)
                            Text(item.video.channelTitle).font(.subheadline.weight(.semibold))
                            Text("•").foregroundStyle(.tertiary)
                            Text(item.video.publishedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        metricChip(BlackstockFormat.compact(item.video.viewCount), "Aufrufe", "eye.fill")
                        metricChip(String(format: "%.0f/h", item.video.viewsPerHour), "Tempo", "bolt.fill")
                        metricChip(BlackstockFormat.duration(item.video.durationSeconds), "Dauer", "clock.fill")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Warum Blackstock das Signal hervorhebt").font(.headline)
                        ForEach(item.reasons) { reason in
                            HStack(alignment: .top, spacing: 10) {
                                ZStack { Circle().fill(Color.blackstockRed.opacity(0.10)).frame(width: 27, height: 27); Image(systemName: reason.strength.symbol).font(.caption.weight(.bold)).foregroundStyle(Color.blackstockRed) }
                                Text(reason.label).font(.subheadline).padding(.top, 4)
                            }
                        }
                    }
                    .padding(15)
                    .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.blackstockBorder))

                    HStack(spacing: 9) {
                        Button { app.startProject(from: item) } label: { Label("Als Projekt starten", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).tint(.blackstockRed)
                        Button("Auf YouTube öffnen") { openYouTube(item.video.id) }
                        Menu("Mehr") {
                            Button("Clip / Remix auf YouTube") { openYouTube(item.video.id) }
                            Button("Video-ID kopieren") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.video.id, forType: .string) }
                        }
                    }
                }
                .padding(22)
                .padding(.bottom, 64)
            }
        } else {
            EmptyState(title: "Trend auswählen", systemImage: "play.rectangle", message: "Wähle links ein Video. Blackstock zeigt Player, Signale und den passenden Produktionsweg direkt daneben.")
        }
    }

    private func metricChip(_ value: String, _ label: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.blackstockRed)
            VStack(alignment: .leading, spacing: 0) { Text(value).font(.subheadline.weight(.bold)); Text(label).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private func openYouTube(_ id: String) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct TrendBrowseRow: View {
    let item: TrendSignal
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: item.video.thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(Color.primary.opacity(0.06)) }
                        .frame(width: 142, height: 80).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(BlackstockFormat.duration(item.video.durationSeconds)).font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 3).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4)).padding(5)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.video.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(item.video.channelTitle) · \(BlackstockFormat.compact(item.video.viewCount)) Aufrufe")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let reason = item.reasons.first {
                        HStack(spacing: 5) { Image(systemName: reason.strength.symbol); Text(reason.label).lineLimit(1) }
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 3)
                if selected { Capsule().fill(Color.blackstockRed).frame(width: 3, height: 44) }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(selected ? Color.blackstockRed.opacity(0.07) : (hovered ? Color.primary.opacity(0.045) : Color.clear))
            )
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Color.blackstockRed.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.11)) { hovered = inside } }
    }
}
#endif
