#if os(macOS)
import SwiftUI
import BlackstockCore

struct ProjectsView: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(app.projects) { project in
                    BlackstockCard {
                        HStack(spacing: 14) {
                            Image(systemName: project.targetFormat == .short ? "rectangle.portrait" : "rectangle").font(.title2).frame(width: 34)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(project.title).font(.headline)
                                Text(project.targetFormat == .short ? "Short" : "Longform").font(.caption).foregroundStyle(.secondary)
                                if !project.workingHook.isEmpty { Text(project.workingHook).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            Text(project.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            Button("Öffnen") { app.openProject(project) }.buttonStyle(.borderedProminent)
                            Menu { Button("Löschen", role: .destructive) { app.deleteProject(project) } } label: { Image(systemName: "ellipsis") }
                        }
                    }
                }
            }.padding(20)
        }.navigationTitle("Projekte").overlay { if app.projects.isEmpty { EmptyState(title: "Noch keine Projekte", systemImage: "square.stack.3d.up", message: "Starte ein Projekt aus Trends oder Ideen.") } }
    }
}
#endif
