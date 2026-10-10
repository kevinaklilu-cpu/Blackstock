#if os(macOS)
import SwiftUI
import BlackstockCore

struct StoryTimelineView: View {
    let scenes: [SupplementalVideoInsertInput]
    let duration: Double
    let leadTitle: String
    let sourceTitles: [UUID: String]
    let canPlay: Bool
    let play: (Double) -> Void
    @State private var expanded = false

    private struct Row {
        let start: Double
        let duration: Double
        let title: String
        let audio: String
        let supplementary: Bool
    }
    private var rows: [Row] {
        var result: [Row] = []
        var cursor = 0.0
        for scene in scenes.sorted(by: { $0.timelineStartSeconds < $1.timelineStartSeconds }) {
            if scene.timelineStartSeconds - cursor > 0.05 {
                result.append(.init(start: cursor, duration: scene.timelineStartSeconds - cursor,
                    title: leadTitle, audio: "Leitvideo · Bild und Ton", supplementary: false))
            }
            result.append(.init(start: scene.timelineStartSeconds, duration: scene.durationSeconds,
                title: sourceTitles[scene.captureID] ?? "Zusatzquelle",
                audio: scene.usesOriginalAudio ? "Zusatzquelle · Bild und Originalton" : "Zusatzbild · Ton vom Leitvideo", supplementary: true))
            cursor = scene.timelineStartSeconds + scene.durationSeconds
        }
        if duration - cursor > 0.05 {
            result.append(.init(start: cursor, duration: duration - cursor,
                title: leadTitle, audio: "Leitvideo · Bild und Ton", supplementary: false))
        }
        return result
    }
    private func time(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("So läuft dein Video").font(.headline)
            Text("\(rows.count) Abschnitte · \(time(duration)) Gesamtlänge")
                .font(.caption).foregroundStyle(.secondary)
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array((expanded ? rows : Array(rows.prefix(8))).enumerated()), id: \.offset) { _, row in
                    Button { play(row.start) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(time(row.start)).font(.caption.monospacedDigit()).frame(width: 42, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(.caption.weight(.semibold)).lineLimit(2)
                                Label(row.audio, systemImage: row.supplementary ? "rectangle.stack.fill" : "film")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(time(row.duration) + " Dauer").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if canPlay { Image(systemName: "play.circle").font(.caption) }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(row.supplementary ? BlackstockDesign.accent.opacity(0.08) : BlackstockDesign.surface,
                                in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(!canPlay)
                }
            }
            if rows.count > 8 {
                Button(expanded ? "Weniger anzeigen" : "Alle \(rows.count) Abschnitte anzeigen") { expanded.toggle() }
                    .font(.caption)
            }
        }
    }
}
#endif
