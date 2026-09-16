#if os(macOS)
import SwiftUI
import AppKit
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
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            if visibleProjects.isEmpty {
                EmptyState(title: "Keine Projekte in diesem Kanal", systemImage: "play.square.stack", message: "Starte aus Trends oder Ideen ein neues Projekt. Es wird automatisch \(app.channel.title) zugeordnet.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 285, maximum: 390), spacing: 15)], spacing: 15) {
                        ForEach(visibleProjects) { project in
                            ProjectLibraryCard(project: project, channelTitle: app.channelTitle(for: project)) {
                                open(project)
                            } delete: {
                                app.deleteProject(project)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 70)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Projekte").font(.largeTitle.bold())
                    Text(app.channel.id == "local" ? "Deine Creator-Library" : "Workspace · \(app.channel.title)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { app.createProject() } label: { Label("Erstellen", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(.blackstockRed)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    stageChip(nil, label: "Alle", count: app.projectsForActiveChannel.count)
                    stageChip(.idea, label: "Ideen", count: count(.idea))
                    stageChip(.editing, label: "Studio", count: count(.editing))
                    stageChip(.rendered, label: "Gerendert", count: count(.rendered))
                    stageChip(.packaging, label: "Packaging", count: count(.packaging))
                    stageChip(.ready, label: "Bereit", count: count(.ready))
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private func stageChip(_ stage: ProjectStage?, label: String, count: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.13)) { filter = stage } } label: {
            HStack(spacing: 6) {
                Text(label).font(.caption.weight(.semibold))
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(filter == stage ? .white.opacity(0.82) : .secondary)
            }
            .foregroundStyle(filter == stage ? .white : .primary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(filter == stage ? Color.blackstockRed : Color.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(filter == stage ? Color.clear : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func count(_ stage: ProjectStage) -> Int {
        app.projectsForActiveChannel.filter { ProjectWorkflowEngine().stage(for: $0) == stage }.count
    }

    private func open(_ project: Project) {
        let stage = ProjectWorkflowEngine().stage(for: project)
        app.activeProject = project
        app.selection = (stage == .ready || stage == .packaging || stage == .rendered) ? .publish : .studio
    }
}

private struct ProjectLibraryCard: View {
    let project: Project
    let channelTitle: String
    let open: () -> Void
    let delete: () -> Void
    @State private var hovered = false

    private var stage: ProjectStage { ProjectWorkflowEngine().stage(for: project) }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(height: project.targetFormat == .short ? 176 : 166)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        Text(stageLabel(stage).uppercased())
                            .font(.caption2.weight(.bold)).tracking(0.45)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(stage == .ready ? Color.green.opacity(0.92) : Color.black.opacity(0.64), in: Capsule())
                            .padding(10)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(project.targetFormat == .short ? "SHORT" : project.effectiveRenderCanvas.label)
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5)).padding(9)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(project.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Menu {
                            Button("Löschen", role: .destructive) { delete() }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(.secondary) }
                        .menuStyle(.borderlessButton).frame(width: 20)
                    }
                    HStack(spacing: 6) {
                        ChannelAvatar(title: channelTitle, size: 22)
                        Text(channelTitle).lineLimit(1)
                        Text("•")
                        Text(project.updatedAt, style: .relative)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if !project.workingHook.isEmpty {
                        Text(project.workingHook).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        progressDot(complete: stage != .idea)
                        progressDot(complete: [.rendered, .packaging, .ready].contains(stage))
                        progressDot(complete: [.packaging, .ready].contains(stage))
                        progressDot(complete: stage == .ready)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(Color.blackstockRed).opacity(hovered ? 1 : 0.66)
                    }
                }
                .padding(13)
            }
            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.primary.opacity(hovered ? 0.13 : 0.07)))
            .shadow(color: .black.opacity(hovered ? 0.12 : 0.035), radius: hovered ? 18 : 7, y: hovered ? 8 : 2)
            .scaleEffect(hovered ? 1.008 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(response: 0.22, dampingFraction: 0.87)) { hovered = inside } }
    }

    @ViewBuilder private var preview: some View {
        if let thumbnail = project.thumbnailURL, let image = NSImage(contentsOf: thumbnail) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.92), Color.blackstockRed.opacity(0.24), Color.black.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                BlackstockBrandMark(size: project.targetFormat == .short ? 38 : 42).opacity(0.94)
                if project.targetFormat == .short {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.07), lineWidth: 1).frame(width: 78, height: 132)
                }
            }
        }
    }

    private func progressDot(complete: Bool) -> some View {
        Capsule().fill(complete ? Color.blackstockRed : Color.primary.opacity(0.10)).frame(width: 22, height: 4)
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
