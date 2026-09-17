#if os(macOS)
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AppKit
import Combine
import BlackstockCore

private enum StudioInspectorTab: String, CaseIterable, Identifiable {
    case script = "Script"
    case project = "Projekt"
    var id: String { rawValue }
}

struct StudioView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var media = NativeMediaService()
    @State private var project = Project(title: "Neues Projekt")
    @State private var player: AVPlayer?
    @State private var importing = false
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var errorMessage: String?
    @State private var inspectorTab: StudioInspectorTab = .script
    @State private var timelineHovered = false
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var stage: ProjectStage { ProjectWorkflowEngine().stage(for: project) }
    private var trimStart: Double { max(project.editInSeconds ?? 0, 0) }
    private var trimEnd: Double { min(project.editOutSeconds ?? duration, max(duration, 0)) }
    private var hasLocalMedia: Bool { project.localMediaURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            studioHeader
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            HSplitView {
                VStack(spacing: 0) {
                    previewStage
                    timelineWorkspace
                }
                .frame(minWidth: 650)

                inspector
                    .frame(minWidth: 390, idealWidth: 455, maxWidth: 520)
            }
        }
        .background(Color.blackstockSurface)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
            switch result {
            case .success(let url): loadLocalVideo(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onAppear {
            if let active = app.activeProject { project = active }
            if project.titleVariants.isEmpty { project.titleVariants = [project.title] }
            if let url = project.localMediaURL { configurePlayer(url) }
        }
        .onChange(of: project) { newValue in app.upsertProject(newValue) }
        .onReceive(ticker) { _ in
            guard let player else { return }
            let seconds = player.currentTime().seconds
            if seconds.isFinite { currentTime = max(seconds, 0) }
            let total = player.currentItem?.duration.seconds ?? 0
            if total.isFinite && total > 0 {
                duration = total
                if project.editOutSeconds == nil { project.editOutSeconds = total }
            }
        }
    }

    private var studioHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Studio").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(app.channel.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                TextField("Projekttitel", text: $project.title)
                    .font(.title2.weight(.bold))
                    .textFieldStyle(.plain)
            }
            Spacer()
            Label("Auto-Save", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            stagePill
            Button { importing = true } label: { Label("Material", systemImage: "plus") }
                .buttonStyle(.bordered)
            Button { renderVideo() } label: {
                HStack(spacing: 7) {
                    if media.isRendering { ProgressView().controlSize(.small) }
                    Image(systemName: "wand.and.stars")
                    Text(media.isRendering ? "Render läuft" : "Rendern")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blackstockRed)
            .disabled(media.isRendering || !hasLocalMedia)
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(.ultraThinMaterial)
    }

    private var stagePill: some View {
        HStack(spacing: 6) {
            Circle().fill(stage == .ready ? Color.green : Color.blackstockRed).frame(width: 7, height: 7)
            Text(stageLabel(stage)).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07)))
    }

    private var previewStage: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.94)
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else if let sourceID = project.sourceVideoID {
                    YouTubePlayer(videoID: sourceID)
                } else {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle().fill(.white.opacity(0.08)).frame(width: 84, height: 84)
                            Image(systemName: "film.stack").font(.system(size: 34, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                        }
                        Text("Material hinzufügen").font(.title3.bold()).foregroundStyle(.white)
                        Text("Öffne eigenes Videomaterial oder starte direkt aus einem Trend. YouTube-Referenzen bleiben Recherchematerial; gerendert wird nur lokales Material.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center).frame(maxWidth: 520)
                        Button("Datei auswählen") { importing = true }
                            .buttonStyle(.borderedProminent).tint(.blackstockRed)
                    }
                }
            }
            .padding(hasLocalMedia || project.sourceVideoID != nil ? 0 : 30)

            HStack(spacing: 7) {
                Label(project.targetFormat == .short ? "Short" : "Longform", systemImage: project.targetFormat == .short ? "rectangle.portrait" : "rectangle")
                Text(project.effectiveRenderCanvas.label)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.58), in: Capsule())
            .padding(14)
        }
        .frame(minHeight: 390)
        .clipped()
    }

    private var timelineWorkspace: some View {
        VStack(spacing: 10) {
            transportBar
            if player != nil {
                VStack(spacing: 9) {
                    HStack {
                        Text("TIMELINE").font(.system(size: 10, weight: .bold)).tracking(0.9).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(time(trimStart)) – \(time(trimEnd))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    timelineStrip
                    HStack(spacing: 9) {
                        Button { project.editInSeconds = min(currentTime, trimEnd) } label: { Label("In setzen", systemImage: "bracket.square") }
                        Button { project.editOutSeconds = max(currentTime, trimStart) } label: { Label("Out setzen", systemImage: "bracket.square.fill") }
                        Button("Reset") { project.editInSeconds = 0; project.editOutSeconds = duration }
                        Spacer()
                        if media.isRendering { Button("Render abbrechen") { media.cancelRender() }.foregroundStyle(.red) }
                    }
                    .font(.caption)
                }
                .padding(14)
                .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.blackstockBorder))
            }
            if let message = media.statusMessage { Label(message, systemImage: "gearshape.2").font(.caption).foregroundStyle(.secondary) }
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red) }
        }
        .padding(14)
        .background(Color.primary.opacity(0.016))
    }

    private var transportBar: some View {
        HStack(spacing: 9) {
            Button { seek(-5) } label: { Image(systemName: "gobackward.5") }.buttonStyle(.plain)
            Button { togglePlayback() } label: {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.09)).frame(width: 38, height: 38)
                    Image(systemName: player?.timeControlStatus == .playing ? "pause.fill" : "play.fill").font(.system(size: 14, weight: .bold))
                }
            }.buttonStyle(.plain)
            Button { seek(5) } label: { Image(systemName: "goforward.5") }.buttonStyle(.plain)

            if player != nil {
                Slider(value: Binding(get: { min(currentTime, max(duration, 0.1)) }, set: { seekAbsolute($0) }), in: 0...max(duration, 0.1))
                    .frame(maxWidth: .infinity)
            } else {
                Capsule().fill(Color.primary.opacity(0.07)).frame(height: 4)
            }
            Text(time(currentTime) + " / " + time(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 92, alignment: .trailing)
            Button { exportThumbnail() } label: { Image(systemName: "photo.badge.plus") }
                .buttonStyle(.plain).disabled(!hasLocalMedia).help("Thumbnail aus aktuellem Frame")
        }
        .padding(.horizontal, 6)
    }

    private var timelineStrip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let total = max(duration, 0.001)
            let startX = width * CGFloat(trimStart / total)
            let endX = width * CGFloat(trimEnd / total)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
                HStack(spacing: 2) {
                    ForEach(0..<28, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(index.isMultiple(of: 3) ? 0.16 : 0.09))
                            .frame(maxWidth: .infinity)
                    }
                }.padding(5)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blackstockRed.opacity(timelineHovered ? 0.18 : 0.12))
                    .frame(width: max(endX - startX, 4))
                    .offset(x: startX)
                Rectangle().fill(Color.blackstockRed).frame(width: 2).offset(x: width * CGFloat(min(currentTime, total) / total))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.07)))
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { timelineHovered = inside } }
        }
        .frame(height: 42)
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector").font(.headline)
                Spacer()
                Picker("", selection: $inspectorTab) {
                    ForEach(StudioInspectorTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            .padding(.horizontal, 16).frame(height: 56)
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            ScrollView {
                Group {
                    switch inspectorTab {
                    case .script: scriptInspector
                    case .project: projectInspector
                    }
                }
                .padding(16)
            }
        }
        .background(.ultraThinMaterial)
    }

    private var scriptInspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            inspectorSection("Hook", icon: "bolt.fill") {
                TextField("Was muss in den ersten Sekunden klar sein?", text: $project.workingHook)
                    .textFieldStyle(.roundedBorder)
            }
            inspectorSection("Titelvarianten", icon: "text.quote") {
                VStack(spacing: 8) {
                    ForEach(project.titleVariants.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 18)
                            TextField("Titel \(index + 1)", text: Binding(get: { project.titleVariants[index] }, set: { project.titleVariants[index] = $0 }))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    HStack {
                        if project.titleVariants.count < 5 { Button("Variante hinzufügen") { project.titleVariants.append("") } }
                        if project.titleVariants.count > 1 { Button("Letzte entfernen") { project.titleVariants.removeLast() }.foregroundStyle(.secondary) }
                    }.font(.caption)
                }
            }
            inspectorSection("Script / Transkript", icon: "text.alignleft") {
                TextEditor(text: $project.transcript)
                    .font(.body.monospaced())
                    .frame(minHeight: 250)
                    .padding(6)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
            }
            inspectorSection("Notizen", icon: "note.text") {
                TextEditor(text: $project.notes)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07)))
            }
            Button { app.upsertProject(project); app.selection = .publish } label: {
                HStack { Text("Für Veröffentlichung vorbereiten"); Spacer(); Image(systemName: "arrow.right") }
            }
            .buttonStyle(.borderedProminent).tint(.blackstockRed)
        }
    }

    private var projectInspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            inspectorSection("Format", icon: "aspectratio") {
                Picker("Ziel", selection: $project.targetFormat) {
                    Text("Short").tag(VideoFormat.short)
                    Text("Longform").tag(VideoFormat.longform)
                }.pickerStyle(.segmented)
                Picker("Canvas", selection: Binding(get: { project.effectiveRenderCanvas }, set: { project.renderCanvas = $0 })) {
                    ForEach(RenderCanvas.allCases) { canvas in Text(canvas.label).tag(canvas) }
                }
            }
            inspectorSection("Schnitt", icon: "scissors") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text("IN").font(.caption2).foregroundStyle(.tertiary); Text(time(trimStart)).font(.headline.monospacedDigit()) }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) { Text("OUT").font(.caption2).foregroundStyle(.tertiary); Text(time(trimEnd)).font(.headline.monospacedDigit()) }
                }
                Button("Auf aktuelle Position als IN") { project.editInSeconds = min(currentTime, trimEnd) }
                Button("Auf aktuelle Position als OUT") { project.editOutSeconds = max(currentTime, trimStart) }
            }
            if project.effectiveRenderCanvas != .source {
                inspectorSection("Reframe", icon: "viewfinder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Horizontal").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { project.effectiveCropAnchorX }, set: { project.cropAnchorX = $0 }), in: 0...1)
                        Text("Vertikal").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { project.effectiveCropAnchorY }, set: { project.cropAnchorY = $0 }), in: 0...1)
                        Text("Der Reframe-Anker verschiebt den sichtbaren Ausschnitt, ohne das Quellvideo zu strecken.").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            inspectorSection("Assets", icon: "externaldrive") {
                if let source = project.localMediaURL { Label(source.lastPathComponent, systemImage: "film").font(.caption) }
                else { Text("Noch keine lokale Quelldatei").font(.caption).foregroundStyle(.secondary) }
                if let output = project.renderedOutputURL {
                    HStack { Label(output.lastPathComponent, systemImage: "checkmark.circle.fill").font(.caption); Spacer(); Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
                }
                if let thumbnail = project.thumbnailURL { Label(thumbnail.lastPathComponent, systemImage: "photo").font(.caption) }
            }
        }
    }

    private func inspectorSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 9) { content() }
                .padding(12)
                .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.blackstockBorder))
        }
    }

    private func loadLocalVideo(_ url: URL) {
        project.localMediaURL = url
        project.renderedOutputURL = nil
        configurePlayer(url)
        app.upsertProject(project)
    }

    private func configurePlayer(_ url: URL) {
        player = AVPlayer(url: url)
        duration = media.sourceDuration(project) ?? 0
        if project.editOutSeconds == nil || (project.editOutSeconds ?? 0) > duration {
            project.editOutSeconds = duration > 0 ? duration : nil
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    private func seek(_ seconds: Double) {
        guard let player else { return }
        let target = max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, player.currentTime().seconds + seconds))
        seekAbsolute(target)
    }

    private func seekAbsolute(_ seconds: Double) {
        guard let player else { return }
        currentTime = max(0, min(seconds, max(duration, 0)))
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
    }

    private func renderVideo() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitized(project.title) + ".mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        media.render(project: project, to: url) { result in
            switch result {
            case .success(let output):
                project.renderedOutputURL = output
                project.lastExportPackageURL = nil
                errorMessage = nil
                app.upsertProject(project)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func exportThumbnail() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitized(project.title) + "-thumbnail.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            project.thumbnailURL = try media.exportThumbnail(project: project, at: currentTime, to: url)
            errorMessage = nil
            app.upsertProject(project)
        } catch { errorMessage = error.localizedDescription }
    }

    private func sanitized(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let clean = value.components(separatedBy: invalid).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Blackstock-Video" : clean
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func stageLabel(_ stage: ProjectStage) -> String {
        switch stage {
        case .idea: return "Idee"
        case .editing: return "Im Studio"
        case .rendered: return "Render fertig"
        case .packaging: return "Packaging"
        case .ready: return "Bereit"
        }
    }
}
#endif
