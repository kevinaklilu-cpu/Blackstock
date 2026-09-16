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

    private var readiness: [ProjectReadinessItem] { ProjectWorkflowEngine().readiness(for: projectForReadiness) }
    private var projectForReadiness: Project { var copy = project; copy.publishTitle = title; copy.publishDescription = description; copy.publishTags = parsedTags; return copy }
    private var parsedTags: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    private var targetChannelID: String? { app.channelID(for: project) ?? (app.channel.id == "local" ? nil : app.channel.id) }
    private var targetChannelTitle: String { targetChannelID.flatMap { id in app.connectedChannels.first(where: { $0.id == id })?.title } ?? app.channelTitle(for: project) }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Veröffentlichen").font(.largeTitle.bold())
                            Text("Packaging und Zielkanal für dieses Video.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let targetChannelID {
                            Menu {
                                ForEach(app.connectedChannels, id: \.id) { channel in
                                    Button(channel.title) { app.moveProject(project, to: channel.id) }
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    ChannelAvatar(title: targetChannelTitle, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(targetChannelTitle).font(.subheadline.weight(.semibold))
                                        Text("Zielkanal").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .help(targetChannelID)
                        }
                    }

                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Details").font(.title2.bold())
                            TextField("Titel", text: $title).textFieldStyle(.roundedBorder)
                            HStack { Text("Titel").font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(title.count) Zeichen").font(.caption.monospacedDigit()).foregroundStyle(title.count > 100 ? .red : .secondary) }
                            Text("Beschreibung").font(.headline)
                            TextEditor(text: $description).frame(minHeight: 160).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                            TextField("Tags, durch Kommas getrennt", text: $tags).textFieldStyle(.roundedBorder)
                            if !project.titleVariants.isEmpty {
                                Text("Titelvarianten").font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack { ForEach(project.titleVariants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { variant in Button(variant) { title = variant }.buttonStyle(.bordered) } }
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Release-Paket exportieren") { exportPackage() }
                            .buttonStyle(.borderedProminent).tint(.blackstockRed)
                            .disabled(!readiness.allSatisfy(\.isComplete))
                        Button("Metadaten kopieren") { saveProject(); copyMetadata() }
                        Button("YouTube Studio für \(targetChannelTitle) öffnen") { saveProject(); openStudio() }
                        Spacer()
                    }
                    if let packageStatus { Text(packageStatus).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                ChannelAvatar(title: targetChannelTitle, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(targetChannelTitle).font(.headline)
                                    Text(targetChannelID == nil ? "Kein verbundener Zielkanal" : "Dieses Video ist diesem Kanal zugeordnet")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if targetChannelID == nil {
                                Button("YouTube-Account verbinden") { app.showOnboardingAgain() }
                                    .buttonStyle(.borderedProminent).tint(.blackstockRed)
                            }
                        }
                    }
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Release-Check").font(.title2.bold())
                            ForEach(readiness) { item in Label(item.label, systemImage: item.isComplete ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isComplete ? .primary : .secondary) }
                        }
                    }
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Assets").font(.headline)
                            if let output = project.renderedOutputURL { Label(output.lastPathComponent, systemImage: "film").font(.caption) } else { Text("Noch kein finaler Render").font(.caption).foregroundStyle(.secondary) }
                            if let thumbnail = project.thumbnailURL, let image = NSImage(contentsOf: thumbnail) {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 190).clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(thumbnail.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            } else { Text("Noch kein Thumbnail").font(.caption).foregroundStyle(.secondary) }
                            Label("Canvas: \(project.effectiveRenderCanvas.label)", systemImage: "rectangle.on.rectangle").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if readiness.allSatisfy(\.isComplete) { Label("Projekt ist release-bereit", systemImage: "checkmark.seal.fill").font(.headline) }
                }
                .frame(width: 350)
            }
            .padding(26)
        }
        .onAppear { loadProject() }
        .onChange(of: title) { _ in saveProject() }
        .onChange(of: description) { _ in saveProject() }
        .onChange(of: tags) { _ in saveProject() }
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

    private func copyMetadata() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(title)\n\n\(description)\n\n\(parsedTags.joined(separator: ", "))", forType: .string)
    }

    private func openStudio() {
        let urlString = targetChannelID.map { "https://studio.youtube.com/channel/\($0)" } ?? "https://studio.youtube.com"
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    private func exportPackage() {
        saveProject()
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Release hier exportieren"
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
