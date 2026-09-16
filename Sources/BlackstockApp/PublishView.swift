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

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Veröffentlichen").font(.largeTitle.bold())
                    BlackstockCard { VStack(alignment: .leading, spacing: 12) {
                        Text("Packaging").font(.title2.bold())
                        TextField("Titel", text: $title).textFieldStyle(.roundedBorder)
                        Text("Beschreibung").font(.headline)
                        TextEditor(text: $description).frame(minHeight: 150).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                        TextField("Tags, durch Kommas getrennt", text: $tags).textFieldStyle(.roundedBorder)
                        if !project.titleVariants.isEmpty { Text("Titelvarianten").font(.headline); ForEach(project.titleVariants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { variant in Button(variant) { title = variant }.buttonStyle(.link) } }
                    } }
                    BlackstockCard { VStack(alignment: .leading, spacing: 12) {
                        Text("Release-Paket").font(.headline)
                        Text("Exportiert Video, Thumbnail, Metadaten und ein maschinenlesbares Manifest gemeinsam in einen Ordner. So bleibt ein fertiges Projekt vollständig übertragbar.").foregroundStyle(.secondary)
                        HStack {
                            Button("Release-Paket exportieren") { exportPackage() }.buttonStyle(.borderedProminent).disabled(!readiness.allSatisfy(\.isComplete))
                            Button("Metadaten kopieren") { saveProject(); copyMetadata() }
                            Button("YouTube Studio öffnen") { saveProject(); openStudio() }
                        }
                        if let packageStatus { Text(packageStatus).font(.caption).foregroundStyle(.secondary) }
                        if let package = project.lastExportPackageURL { Button("Paket im Finder") { NSWorkspace.shared.activateFileViewerSelecting([package]) } }
                    } }
                }.frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    BlackstockCard { VStack(alignment: .leading, spacing: 10) {
                        Text("Release-Check").font(.title2.bold())
                        ForEach(readiness) { item in Label(item.label, systemImage: item.isComplete ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isComplete ? .primary : .secondary) }
                    } }
                    BlackstockCard { VStack(alignment: .leading, spacing: 10) {
                        Text("Assets").font(.headline)
                        if let output = project.renderedOutputURL { Label(output.lastPathComponent, systemImage: "film").font(.caption) } else { Text("Noch kein finaler Render").font(.caption).foregroundStyle(.secondary) }
                        if let thumbnail = project.thumbnailURL, let image = NSImage(contentsOf: thumbnail) { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 10)); Text(thumbnail.lastPathComponent).font(.caption).foregroundStyle(.secondary) } else { Text("Noch kein Thumbnail").font(.caption).foregroundStyle(.secondary) }
                        Label("Canvas: \(project.effectiveRenderCanvas.label)", systemImage: "rectangle.on.rectangle")
                            .font(.caption).foregroundStyle(.secondary)
                    } }
                    if readiness.allSatisfy(\.isComplete) { Label("Projekt ist release-bereit", systemImage: "checkmark.seal.fill").font(.headline) } else { Text("Fehlende Punkte bleiben sichtbar; Blackstock erfindet keinen Fertig-Status.").font(.caption).foregroundStyle(.secondary) }
                }.frame(width: 340)
            }.padding(24)
        }
        .onAppear { loadProject() }
        .onChange(of: title) { _ in saveProject() }
        .onChange(of: description) { _ in saveProject() }
        .onChange(of: tags) { _ in saveProject() }
    }

    private func loadProject() { guard let active = app.activeProject else { return }; project = active; title = active.publishTitle ?? active.title; description = active.publishDescription ?? ""; tags = (active.publishTags ?? []).joined(separator: ", ") }
    private func saveProject() { project.publishTitle = title; project.publishDescription = description; project.publishTags = parsedTags; if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { project.title = title }; app.upsertProject(project) }
    private func copyMetadata() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(title)\n\n\(description)\n\n\(parsedTags.joined(separator: ", "))", forType: .string) }
    private func openStudio() { if let url = URL(string: "https://studio.youtube.com") { NSWorkspace.shared.open(url) } }
    private func exportPackage() {
        saveProject()
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Release hier exportieren"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do { let url = try ReleasePackageService().export(project: project, to: directory); project.lastExportPackageURL = url; app.upsertProject(project); packageStatus = "Release-Paket exportiert: \(url.lastPathComponent)" }
        catch { packageStatus = error.localizedDescription }
    }
}
#endif
