#if os(macOS)
import SwiftUI
import BlackstockCore

struct ProjectsView: View {
    @EnvironmentObject private var app: AppState
    @State private var filter: ProjectStage?

    private var visibleProjects: [Project] {
        let source = app.projectsForActiveChannel
        guard let filter else { return source }
        return source.filter { ProjectWorkflowEngine().stage(for: $0) == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Projekte").font(.largeTitle.bold())
                    Text(app.channel.id == "local" ? "Alle lokalen Projekte" : "Workspace · \(app.channel.title)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Alle") { filter = nil }
                    ForEach(ProjectStage.allCases, id: \.self) { stage in Button(stageLabel(stage)) { filter = stage } }
                } label: {
                    Label(filter.map(stageLabel) ?? "Alle Status", systemImage: "line.3.horizontal.decrease.circle")
                }
                Button { app.createProject() } label: { Label("Erstellen", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(.blackstockRed)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)

            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)

            if visibleProjects.isEmpty {
                EmptyState(title: "Keine Projekte in diesem Kanal", systemImage: "play.square.stack", message: "Starte aus Trends oder Ideen ein neues Projekt. Es wird automatisch \(app.channel.title) zugeordnet.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleProjects) { project in
                            projectRow(project)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let stage = ProjectWorkflowEngine().stage(for: project)
        return Button {
            app.activeProject = project
            app.selection = (stage == .ready || stage == .packaging || stage == .rendered) ? .publish : .studio
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.055))
                    Image(systemName: project.targetFormat == .short ? "rectangle.portrait.fill" : "rectangle.fill")
                        .foregroundStyle(project.targetFormat == .short ? Color.blackstockRed : Color.secondary)
                }
                .frame(width: 58, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.title).font(.headline).lineLimit(1)
                        Text(stageLabel(stage)).font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    HStack(spacing: 7) {
                        Text(project.targetFormat == .short ? "Short" : "Longform")
                        Text("•")
                        Text(app.channelTitle(for: project))
                        if !project.workingHook.isEmpty { Text("•"); Text(project.workingHook).lineLimit(1) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(project.updatedAt, style: .relative).font(.caption).foregroundStyle(.tertiary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                Menu {
                    Button("Löschen", role: .destructive) { app.deleteProject(project) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 24)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.primary.opacity(0.055)))
        }
        .buttonStyle(.plain)
    }

    private func stageLabel(_ stage: ProjectStage) -> String {
        switch stage {
        case .idea: return "Idee"
        case .editing: return "Studio"
        case .rendered: return "Gerendert"
        case .packaging: return "Packaging"
        case .ready: return "Bereit"
        }
    }
}
#endif
