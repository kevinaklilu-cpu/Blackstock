#if os(macOS)
import SwiftUI
import AppKit
import BlackstockCore

struct PublishView: View {
    @EnvironmentObject private var app: AppState
    @State private var project = Project(title: "Neues Projekt")
    @State private var title = ""
    @State private var description = ""
    @State private var tags = ""
    @State private var packageStatus: String?
    @State private var privacyStatus = "private"
    @State private var isUploading = false
    @State private var uploadProgress = 0.0
    @State private var uploadMessage: String?
    @State private var uploadedVideoID: String?
    @State private var previewHovered = false

    private var readiness: [ProjectReadinessItem] { ProjectWorkflowEngine().readiness(for: projectForReadiness) }
    private var readinessCount: Int { readiness.filter(\.isComplete).count }
    private var readinessProgress: Double { readiness.isEmpty ? 0 : Double(readinessCount) / Double(readiness.count) }
    private var projectForReadiness: Project {
        var copy = project
        copy.publishTitle = title
        copy.publishDescription = description
        copy.publishTags = parsedTags
        return copy
    }
    private var parsedTags: [String] {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var targetChannelID: String? { app.channelID(for: project) ?? (app.channel.id == "local" ? nil : app.channel.id) }
    private var targetChannelTitle: String {
        targetChannelID.flatMap { id in app.connectedChannels.first(where: { $0.id == id })?.title } ?? app.channelTitle(for: project)
    }
    private var canUploadDirectly: Bool {
        guard let targetChannelID else { return false }
        return readiness.allSatisfy(\.isComplete) && GoogleYouTubeAuth.isAuthenticated(channelID: targetChannelID) && !isUploading
    }

    var body: some View {
        VStack(spacing: 0) {
            publishHeader
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        metadataSection
                        releaseSection
                    }
                    .padding(20)
                }
                .frame(minWidth: 610)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        youtubePreview
                        releaseChecklist
                        assetSummary
                    }
                    .padding(18)
                }
                .frame(minWidth: 360, idealWidth: 410, maxWidth: 470)
                .background(.ultraThinMaterial)
            }
        }
        .background(Color.blackstockSurface)
        .onAppear { loadProject() }
        .onChange(of: title) { _ in saveProject() }
        .onChange(of: description) { _ in saveProject() }
        .onChange(of: tags) { _ in saveProject() }
    }

    private var publishHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text("Publishing").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(targetChannelTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(project.title).font(.title2.bold()).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(readinessProgress == 1 ? Color.green : Color.blackstockRed).frame(width: 7, height: 7)
                Text("\(readinessCount)/\(readiness.count) bereit").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07)))

            Menu {
                ForEach(app.connectedChannels, id: \.id) { channel in
                    Button(channel.title) {
                        app.moveProject(project, to: channel.id)
                        uploadMessage = nil
                        uploadedVideoID = nil
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    ChannelAvatar(title: targetChannelTitle, size: 32)
                    Text(targetChannelTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .menuStyle(.borderlessButton)

            Button { startDirectUpload() } label: {
                HStack(spacing: 7) {
                    if isUploading { ProgressView().controlSize(.small) }
                    Image(systemName: "arrow.up.circle.fill")
                    Text(isUploading ? "Upload läuft" : "Veröffentlichen")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blackstockRed)
            .disabled(!canUploadDirectly)
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(.ultraThinMaterial)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Video-Details", subtitle: "Was Zuschauer auf YouTube sehen", icon: "text.alignleft")
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text("Titel").font(.subheadline.weight(.semibold)); Spacer(); Text("\(title.count)/100").font(.caption.monospacedDigit()).foregroundStyle(title.count > 100 ? .red : .secondary) }
                    TextField("Titel", text: $title).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Beschreibung").font(.subheadline.weight(.semibold))
                    TextEditor(text: $description)
                        .frame(minHeight: 210)
                        .padding(6)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.07)))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tags").font(.subheadline.weight(.semibold))
                    TextField("Tags, durch Kommas getrennt", text: $tags).textFieldStyle(.roundedBorder)
                }
                if !project.titleVariants.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Titelvarianten").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(project.titleVariants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { variant in
                                    Button(variant) { title = variant }
                                        .buttonStyle(.plain)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(Color.primary.opacity(0.055), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07)))
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))
        }
    }

    private var releaseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Direkt zu YouTube", subtitle: "Upload, Sichtbarkeit und Export", icon: "arrow.up.circle.fill")
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sichtbarkeit").font(.subheadline.weight(.semibold))
                        Text("Du kannst die Sichtbarkeit später in YouTube Studio ändern.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Sichtbarkeit", selection: $privacyStatus) {
                        Text("Privat").tag("private")
                        Text("Nicht gelistet").tag("unlisted")
                        Text("Öffentlich").tag("public")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }

                if isUploading || uploadProgress > 0 {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(uploadMessage ?? "Upload …").font(.caption.weight(.medium)); Spacer(); Text("\(Int(uploadProgress * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        ProgressView(value: uploadProgress).progressViewStyle(.linear)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 10) {
                    Button { startDirectUpload() } label: {
                        HStack(spacing: 8) {
                            if isUploading { ProgressView().controlSize(.small) }
                            Image(systemName: "arrow.up.circle.fill")
                            Text(isUploading ? "Wird hochgeladen …" : "Zu \(targetChannelTitle) hochladen")
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.blackstockRed).disabled(!canUploadDirectly)

                    Button("Release-Paket exportieren") { exportPackage() }
                        .disabled(!readiness.allSatisfy(\.isComplete) || isUploading)
                    Button("Metadaten kopieren") { saveProject(); copyMetadata() }
                    Spacer()
                }

                if let uploadedVideoID {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Upload abgeschlossen").font(.subheadline.weight(.semibold))
                            Text("YouTube-ID · \(uploadedVideoID)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Video öffnen") { openVideo(uploadedVideoID) }
                        Button("Studio") { openStudio() }
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if let packageStatus { Text(packageStatus).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(16)
            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))
        }
    }

    private var youtubePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YouTube-Vorschau").font(.headline)
                Spacer()
                Text(privacyLabel).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).background(Color.primary.opacity(0.06), in: Capsule())
            }
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(Color.black.opacity(0.92))
                if let thumbnail = project.thumbnailURL, let image = NSImage(contentsOf: thumbnail) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: "photo").font(.system(size: 31)).foregroundStyle(.white.opacity(0.5))
                        Text("Thumbnail fehlt").font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                }
                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(15)
                    .background(.black.opacity(0.62), in: Circle())
            }
            .frame(height: 205)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .scaleEffect(previewHovered ? 1.006 : 1)
            .shadow(color: .black.opacity(previewHovered ? 0.16 : 0.06), radius: previewHovered ? 18 : 8, y: 8)
            .onHover { inside in withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) { previewHovered = inside } }

            HStack(alignment: .top, spacing: 10) {
                ChannelAvatar(title: targetChannelTitle, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.isEmpty ? project.title : title).font(.headline).lineLimit(2)
                    Text(targetChannelTitle).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        Text(project.targetFormat == .short ? "Short" : "Longform")
                        Text("•")
                        Text(project.effectiveRenderCanvas.label)
                    }.font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.blackstockBorder))
    }

    private var releaseChecklist: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { Text("Release-Check").font(.headline); Spacer(); Text("\(Int(readinessProgress * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: readinessProgress).progressViewStyle(.linear)
            ForEach(readiness) { item in
                HStack(spacing: 9) {
                    Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isComplete ? Color.green : Color.secondary)
                    Text(item.label).font(.subheadline)
                    Spacer()
                }
            }
            if let targetChannelID {
                HStack(spacing: 9) {
                    Image(systemName: GoogleYouTubeAuth.isAuthenticated(channelID: targetChannelID) ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(GoogleYouTubeAuth.isAuthenticated(channelID: targetChannelID) ? Color.green : Color.orange)
                    Text(GoogleYouTubeAuth.isAuthenticated(channelID: targetChannelID) ? "Upload autorisiert" : "YouTube erneut verbinden").font(.subheadline)
                }
            } else {
                Button("YouTube-Account verbinden") { app.showOnboardingAgain() }.buttonStyle(.borderedProminent).tint(.blackstockRed)
            }
        }
        .padding(14)
        .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))
    }

    private var assetSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assets").font(.headline)
            if let output = project.renderedOutputURL { assetRow("Finaler Render", value: output.lastPathComponent, icon: "film.fill") }
            else { assetRow("Finaler Render", value: "Fehlt", icon: "film") }
            if let thumbnail = project.thumbnailURL { assetRow("Thumbnail", value: thumbnail.lastPathComponent, icon: "photo.fill") }
            else { assetRow("Thumbnail", value: "Fehlt", icon: "photo") }
            assetRow("Canvas", value: project.effectiveRenderCanvas.label, icon: "aspectratio")
            assetRow("Format", value: project.targetFormat == .short ? "Short" : "Longform", icon: project.targetFormat == .short ? "rectangle.portrait" : "rectangle")
        }
        .padding(14)
        .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))
    }

    private func sectionHeader(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(Color.blackstockRed.opacity(0.1)).frame(width: 38, height: 38); Image(systemName: icon).foregroundStyle(Color.blackstockRed) }
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.title3.bold()); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func assetRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.caption2).foregroundStyle(.tertiary); Text(value).font(.caption).lineLimit(1) }
            Spacer()
        }
    }

    private var privacyLabel: String {
        switch privacyStatus { case "public": return "Öffentlich"; case "unlisted": return "Nicht gelistet"; default: return "Privat" }
    }

    private func loadProject() {
        guard let active = app.activeProject else { return }
        project = active
        if app.channelID(for: active) == nil, app.channel.id != "local" { app.moveProject(active, to: app.channel.id) }
        title = active.publishTitle ?? active.title
        description = active.publishDescription ?? ""
        tags = (active.publishTags ?? []).joined(separator: ", ")
    }

    private func saveProject() {
        project.publishTitle = title
        project.publishDescription = description
        project.publishTags = parsedTags
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { project.title = title }
        app.upsertProject(project)
    }

    private func startDirectUpload() {
        guard let channelID = targetChannelID else { return }
        saveProject()
        isUploading = true
        uploadProgress = 0
        uploadMessage = "Upload wird vorbereitet …"
        uploadedVideoID = nil
        let uploadProject = projectForReadiness
        Task {
            do {
                let videoID = try await YouTubePublishingService().upload(project: uploadProject, channelID: channelID, privacyStatus: privacyStatus) { value, message in
                    uploadProgress = value
                    uploadMessage = message
                }
                uploadedVideoID = videoID
                uploadProgress = 1
                uploadMessage = "Upload abgeschlossen. Das Video gehört jetzt zu \(targetChannelTitle)."
                isUploading = false
            } catch {
                uploadMessage = error.localizedDescription
                isUploading = false
            }
        }
    }

    private func copyMetadata() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(title)\n\n\(description)\n\n\(parsedTags.joined(separator: ", "))", forType: .string)
    }

    private func openStudio() {
        let urlString = targetChannelID.map { "https://studio.youtube.com/channel/\($0)" } ?? "https://studio.youtube.com"
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    private func openVideo(_ id: String) {
        if let url = URL(string: "https://www.youtube.com/watch?v=\(id)") { NSWorkspace.shared.open(url) }
    }

    private func exportPackage() {
        saveProject()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Release hier exportieren"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let url = try ReleasePackageService().export(project: project, to: directory)
            project.lastExportPackageURL = url
            app.upsertProject(project)
            packageStatus = "Release-Paket exportiert: \(url.lastPathComponent)"
        } catch { packageStatus = error.localizedDescription }
    }
}
#endif
