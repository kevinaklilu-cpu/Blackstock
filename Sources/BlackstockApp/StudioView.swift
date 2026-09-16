#if os(macOS)
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import BlackstockCore

struct StudioView: View {
    @EnvironmentObject private var app: AppState
    @State private var project = Project(title: "Neues Projekt")
    @State private var player: AVPlayer?
    @State private var importing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Projekttitel", text: $project.title).font(.title3.weight(.semibold)).textFieldStyle(.plain)
                Spacer()
                Picker("Format", selection: $project.targetFormat) { Text("Short").tag(VideoFormat.short); Text("Longform").tag(VideoFormat.longform) }.frame(width: 180)
                Button("Eigene Datei öffnen") { importing = true }
            }.padding(14)
            Divider()
            HSplitView {
                VStack(spacing: 12) {
                    if let player {
                        VideoPlayer(player: player).frame(minHeight: 360)
                    } else if let sourceID = project.sourceVideoID {
                        YouTubePlayer(videoID: sourceID).frame(minHeight: 360)
                    } else {
                        EmptyState(title: "Material hinzufügen", systemImage: "film", message: "Öffne eine eigene Datei oder starte ein Projekt direkt aus Trends.")
                    }
                    HStack {
                        Button("Zurück 5 s") { seek(-5) }
                        Button(player?.timeControlStatus == .playing ? "Pause" : "Abspielen") { togglePlayback() }
                        Button("Vor 5 s") { seek(5) }
                        Spacer()
                    }
                }.padding(16).frame(minWidth: 560)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Text & Struktur").font(.headline)
                    Text("Schneide Gedanken, Hook und Aufbau hier vor. Die Änderungen bleiben im Projekt erhalten und bilden die Grundlage für den finalen Schnitt.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $project.transcript).font(.body.monospaced()).frame(minHeight: 240).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    Text("Notizen").font(.headline)
                    TextEditor(text: $project.notes).frame(minHeight: 120).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    Spacer()
                    Button("Für Veröffentlichung vorbereiten") { app.activeProject = project; app.selection = .publish }.buttonStyle(.borderedProminent)
                }.padding(16).frame(minWidth: 360, idealWidth: 440)
            }
        }
        .navigationTitle("Studio")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            if case .success(let url) = result { project.localMediaURL = url; player = AVPlayer(url: url) }
        }
        .onAppear {
            if let active = app.activeProject { project = active }
            if let url = project.localMediaURL { player = AVPlayer(url: url) }
        }
        .onChange(of: project) { newValue in app.activeProject = newValue }
    }

    private func togglePlayback() {
        guard let player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    private func seek(_ seconds: Double) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: max(0, player.currentTime().seconds + seconds), preferredTimescale: 600))
    }
}
#endif
