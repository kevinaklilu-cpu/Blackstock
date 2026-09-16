#if os(macOS)
import SwiftUI
import AppKit
struct PublishView: View {
    @EnvironmentObject private var app: AppState
    @State private var title = "", description = "", tags = ""
    var body: some View { Form { Section("Video") { TextField("Titel", text: $title); TextEditor(text: $description).frame(minHeight: 120); TextField("Tags, durch Kommas getrennt", text: $tags) }; Section("Packaging") { Text("Bereite Titel und Beschreibung hier vor. Blackstock öffnet anschließend den offiziellen YouTube-Studio-Uploadfluss.").foregroundStyle(.secondary); HStack { Button("Metadaten kopieren") { copyMetadata() }; Button("YouTube Studio öffnen") { openStudio() }.buttonStyle(.borderedProminent) } } }.formStyle(.grouped).navigationTitle("Veröffentlichen").onAppear { if let project = app.activeProject, title.isEmpty { title = project.title } } }
    private func copyMetadata() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("\(title)\n\n\(description)\n\n\(tags)", forType: .string) }
    private func openStudio() { if let url = URL(string: "https://studio.youtube.com") { NSWorkspace.shared.open(url) } }
}
#endif
