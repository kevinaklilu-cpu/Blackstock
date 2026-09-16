#if os(macOS)
import SwiftUI
import BlackstockCore

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var trends: TrendViewModel
    let apiKey: String

    private let workflow = ProjectWorkflowEngine()
    private var readyProjects: Int { app.projects.filter { workflow.stage(for: $0) == .ready }.count }
    private var activeProjects: Int { app.projects.filter { [.editing, .rendered, .packaging].contains(workflow.stage(for: $0)) }.count }

    init(trends: TrendViewModel, apiKey: String) {
        self.trends = trends
        self.apiKey = apiKey
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blackstock").font(.largeTitle.bold())
                    Text("Von Markt-Signal bis fertigem Upload-Paket in einem Workflow.").font(.title3).foregroundStyle(.secondary)
                    if app.channel.id != "local" { Text("Für \(app.channel.title) · Basis: letzte öffentliche Uploads").font(.caption).foregroundStyle(.secondary) }
                }

                HStack(spacing: 12) {
                    workflowCard(title: "Trends", value: "\(trends.items.count)", subtitle: "geladene Signale", action: .trends)
                    workflowCard(title: "Produktion", value: "\(activeProjects)", subtitle: "aktive Projekte", action: .projects)
                    workflowCard(title: "Bereit", value: "\(readyProjects)", subtitle: "komplette Upload-Pakete", action: .publish)
                }

                if let error = trends.errorMessage, trends.items.isEmpty {
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Live-Trends sind noch nicht verbunden").font(.headline)
                            Text(error).foregroundStyle(.secondary)
                            Button("Einstellungen öffnen") { app.selection = .settings }
                        }
                    }
                }

                HStack {
                    Text("Was du jetzt tun kannst").font(.title2.bold())
                    Spacer()
                    Button("Recherche öffnen") { app.selection = .research }
                    Button("Neues Projekt") {
                        let project = Project(title: "Neues Projekt", titleVariants: ["Neues Projekt"], publishTitle: "Neues Projekt")
                        app.upsertProject(project)
                        app.selection = .studio
                    }.buttonStyle(.borderedProminent)
                }

                if !app.projects.isEmpty {
                    BlackstockCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Zuletzt bearbeitet").font(.headline)
                            ForEach(app.projects.prefix(3)) { project in
                                Button {
                                    app.activeProject = project
                                    app.selection = workflow.stage(for: project) == .ready ? .publish : .studio
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(project.title).font(.headline)
                                            Text(stageLabel(workflow.stage(for: project))).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(project.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }

                Text("Aktuelle Markt-Signale").font(.title2.bold())
                ForEach(trends.items.prefix(6)) { trend in
                    Button { app.openTrend(trend) } label: {
                        HStack(spacing: 14) {
                            AsyncImage(url: trend.video.thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(.quaternary) }
                                .frame(width: 150, height: 84).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(trend.video.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                Text(trend.video.channelTitle).font(.subheadline).foregroundStyle(.secondary)
                                if let reason = trend.reasons.first { Label(reason.label, systemImage: reason.strength.symbol).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(trend.recommendedFormat == .short ? "Short" : "Longform").font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(.quaternary, in: Capsule())
                        }.padding(12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(24)
        }
        .task { if trends.items.isEmpty { trends.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel) } }
    }

    private func workflowCard(title: String, value: String, subtitle: String, action: AppState.Section) -> some View {
        Button { app.selection = action } label: {
            BlackstockCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }

    private func stageLabel(_ stage: ProjectStage) -> String {
        switch stage {
        case .idea: return "Idee vorbereitet"
        case .editing: return "Im Studio"
        case .rendered: return "Gerendert"
        case .packaging: return "Packaging offen"
        case .ready: return "Bereit zur Veröffentlichung"
        }
    }
}
#endif
