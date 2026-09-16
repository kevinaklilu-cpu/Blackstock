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

    private var readiness: [ProjectReadinessItem] { ProjectWorkflowEngine().readiness(for: projectForReadiness) }
    private var projectForReadiness: Project {
        var copy = project
        copy.publishTitle = title
        copy.publishDescription = description
        copy.publishTags = parsedTags
        return copy
    }
    private var parsedTags: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Veröffentlichen").font(.largeTitle.bold())
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Packaging").font(.title2.bold())
                            TextField("Titel", text: $title).textFieldStyle(.roundedBorder)
                            Text("Beschreibung").font(.headline)
                            TextEditor(text: $description).frame(minHeight: 150).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                            TextField("Tags, durch Kommas getrennt", text: $tags).textFieldStyle(.roundedBorder)
                            if !project.titleVariants.isEmpty {
                                Text("Titelvarianten").font(.headline)
                                ForEach(project.titleVariants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { variant in
                                    Button(variant) { title = variant }.buttonStyle(.link)
                                }
                            }
                        }
                    }
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Übergabe an YouTube").font(.headline)
                            Text("Blackstock hält Render, Thumbnail und Metadaten zusammen. Der Upload selbst wird im offiziellen YouTube-Studio-Workflow abgeschlossen.").foregroundStyle(.secondary)
                            HStack {
                                Button("Metadaten kopieren") { saveProject(); copyMetadata() }
                                Button("YouTube Studio öffnen") { saveProject(); openStudio() }.buttonStyle(.borderedProminent)
                                if let output = project.renderedOutputURL { Button("Video im Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Release-Check").font(.title2.bold())
                            ForEach(readiness) { item in
                                Label(item.label, systemImage: item.isComplete ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isComplete ? .primary : .secondary)
                            }
                        }
                    }
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Assets").font(.headline)
                            if let output = project.renderedOutputURL {
                                Label(output.lastPathComponent, systemImage: "film").font(.caption)
                            } else { Text("Noch kein finaler Render").font(.caption).foregroundStyle(.secondary) }
                            if let thumbnail = project.thumbnailURL, let image = NSImage(contentsOf: thumbnail) {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(thumbnail.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            } else { Text("Noch kein Thumbnail").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if readiness.allSatisfy(\.isComplete) {
                        Label("Projekt ist für die Veröffentlichung vorbereitet", systemImage: "checkmark.seal.fill").font(.headline)
                    } else {
                        Text("Fehlende Punkte werden absichtlich sichtbar gelassen; Blackstock erfindet keinen Fertig-Status.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(width: 340)
            }.padding(24)
        }
        .onAppear { loadProject() }
        .onChange(of: title) { _ in saveProject() }
        .onChange(of: description) { _ in saveProject() }
        .onChange(of: tags) { _ in saveProject() }
    }

    private func loadProject() {
        guard let active = app.activeProject else { return }
        project = active
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
        if let url = URL(string: "https://studio.youtube.com") { NSWorkspace.shared.open(url) }
    }
}
#endif
