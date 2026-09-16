#if os(macOS)
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AppKit
import Combine
import BlackstockCore

struct StudioView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var media = NativeMediaService()
    @State private var project = Project(title: "Neues Projekt")
    @State private var player: AVPlayer?
    @State private var importing = false
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var errorMessage: String?
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) { toolbar; Divider(); HSplitView { previewPane.frame(minWidth: 590); editorPane.frame(minWidth: 400, idealWidth: 470) } }
            .navigationTitle("Studio")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in switch result { case .success(let url): loadLocalVideo(url); case .failure(let error): errorMessage = error.localizedDescription } }
            .onAppear { if let active = app.activeProject { project = active }; if project.titleVariants.isEmpty { project.titleVariants = [project.title] }; if let url = project.localMediaURL { configurePlayer(url) } }
            .onChange(of: project) { newValue in app.upsertProject(newValue) }
            .onReceive(ticker) { _ in guard let player else { return }; let seconds = player.currentTime().seconds; if seconds.isFinite { currentTime = max(seconds, 0) }; let total = player.currentItem?.duration.seconds ?? 0; if total.isFinite && total > 0 { duration = total; if project.editOutSeconds == nil { project.editOutSeconds = total } } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            TextField("Projekttitel", text: $project.title).font(.title3.weight(.semibold)).textFieldStyle(.plain)
            Spacer()
            Picker("Format", selection: $project.targetFormat) { Text("Short").tag(VideoFormat.short); Text("Longform").tag(VideoFormat.longform) }.frame(width: 160)
            Picker("Canvas", selection: Binding(get: { project.effectiveRenderCanvas }, set: { project.renderCanvas = $0 })) { ForEach(RenderCanvas.allCases) { canvas in Text(canvas.label).tag(canvas) } }.frame(width: 140)
            Button("Eigene Datei öffnen") { importing = true }
            if media.isRendering { Button("Abbrechen") { media.cancelRender() } }
        }.padding(14)
    }

    private var previewPane: some View {
        VStack(spacing: 14) {
            Group { if let player { VideoPlayer(player: player).frame(minHeight: 360) } else if let sourceID = project.sourceVideoID { YouTubePlayer(videoID: sourceID).frame(minHeight: 360) } else { EmptyState(title: "Material hinzufügen", systemImage: "film", message: "Öffne eine eigene Datei oder starte ein Projekt direkt aus Trends. YouTube-Referenzen dienen als Recherche; gerendert wird nur lokales Material.") } }
            if player != nil { trimPanel }
            HStack { Button("Zurück 5 s") { seek(-5) }; Button(player?.timeControlStatus == .playing ? "Pause" : "Abspielen") { togglePlayback() }; Button("Vor 5 s") { seek(5) }; Spacer(); Text(time(currentTime) + " / " + time(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if let message = media.statusMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }.padding(16)
    }

    private var trimPanel: some View {
        BlackstockCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Schnitt & Reframe").font(.headline); Spacer(); Text("\(time(project.editInSeconds ?? 0)) – \(time(project.editOutSeconds ?? duration))").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                HStack { Button("In = aktuelle Position") { project.editInSeconds = min(currentTime, project.editOutSeconds ?? duration) }; Button("Out = aktuelle Position") { project.editOutSeconds = max(currentTime, project.editInSeconds ?? 0) }; Button("Zurücksetzen") { project.editInSeconds = 0; project.editOutSeconds = duration }; Spacer() }
                if project.effectiveRenderCanvas != .source {
                    HStack { Text("Horizontal").frame(width: 75, alignment: .leading); Slider(value: Binding(get: { project.effectiveCropAnchorX }, set: { project.cropAnchorX = $0 }), in: 0...1); Text("Vertikal").frame(width: 55, alignment: .trailing); Slider(value: Binding(get: { project.effectiveCropAnchorY }, set: { project.cropAnchorY = $0 }), in: 0...1) }.font(.caption)
                    Text("Reframe-Anker verschiebt den sichtbaren Ausschnitt, ohne das Quellvideo zu strecken.").font(.caption2).foregroundStyle(.secondary)
                }
                HStack { Button("Video rendern") { renderVideo() }.buttonStyle(.borderedProminent).disabled(media.isRendering || project.localMediaURL == nil); Button("Thumbnail aus aktuellem Frame") { exportThumbnail() }.disabled(project.localMediaURL == nil); if let output = project.renderedOutputURL { Button("Render im Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } } }
            }
        }
    }

    private var editorPane: some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            Text("Hook").font(.headline); TextField("Was muss in den ersten Sekunden klar sein?", text: $project.workingHook).textFieldStyle(.roundedBorder)
            Text("Titelvarianten").font(.headline)
            ForEach(project.titleVariants.indices, id: \.self) { index in TextField("Titel \(index + 1)", text: Binding(get: { project.titleVariants[index] }, set: { project.titleVariants[index] = $0 })) }
            HStack { if project.titleVariants.count < 5 { Button("Titelvariante hinzufügen") { project.titleVariants.append("") } }; if project.titleVariants.count > 1 { Button("Letzte entfernen") { project.titleVariants.removeLast() } } }
            Divider(); Text("Text & Struktur").font(.headline); Text("Bearbeite Script oder Transkript direkt im Projekt. Blackstock speichert Änderungen automatisch.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $project.transcript).font(.body.monospaced()).frame(minHeight: 230).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            Text("Notizen").font(.headline); TextEditor(text: $project.notes).frame(minHeight: 110).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            Divider(); Button("Für Veröffentlichung vorbereiten") { app.upsertProject(project); app.selection = .publish }.buttonStyle(.borderedProminent)
        }.padding(16) }
    }

    private func loadLocalVideo(_ url: URL) { project.localMediaURL = url; project.renderedOutputURL = nil; configurePlayer(url); app.upsertProject(project) }
    private func configurePlayer(_ url: URL) { player = AVPlayer(url: url); duration = media.sourceDuration(project) ?? 0; if project.editOutSeconds == nil || (project.editOutSeconds ?? 0) > duration { project.editOutSeconds = duration > 0 ? duration : nil } }
    private func togglePlayback() { guard let player else { return }; player.timeControlStatus == .playing ? player.pause() : player.play() }
    private func seek(_ seconds: Double) { guard let player else { return }; let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, player.currentTime().seconds + seconds)); player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) }
    private func renderVideo() { let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.canCreateDirectories = true; panel.nameFieldStringValue = sanitized(project.title) + ".mp4"; guard panel.runModal() == .OK, let url = panel.url else { return }; media.render(project: project, to: url) { result in switch result { case .success(let output): project.renderedOutputURL = output; project.lastExportPackageURL = nil; errorMessage = nil; app.upsertProject(project); case .failure(let error): errorMessage = error.localizedDescription } } }
    private func exportThumbnail() { let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.canCreateDirectories = true; panel.nameFieldStringValue = sanitized(project.title) + "-thumbnail.png"; guard panel.runModal() == .OK, let url = panel.url else { return }; do { project.thumbnailURL = try media.exportThumbnail(project: project, at: currentTime, to: url); errorMessage = nil; app.upsertProject(project) } catch { errorMessage = error.localizedDescription } }
    private func sanitized(_ value: String) -> String { let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>"); let clean = value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines); return clean.isEmpty ? "Blackstock-Video" : clean }
    private func time(_ seconds: Double) -> String { guard seconds.isFinite && seconds >= 0 else { return "0:00" }; let total = Int(seconds.rounded(.down)); return String(format: "%d:%02d", total / 60, total % 60) }
}
#endif
