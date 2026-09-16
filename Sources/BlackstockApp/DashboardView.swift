#if os(macOS)
import SwiftUI
import BlackstockCore

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var trends: TrendViewModel
    let apiKey: String

    private let workflow = ProjectWorkflowEngine()
    private var channelProjects: [Project] { app.projectsForActiveChannel }
    private var readyProjects: Int { channelProjects.filter { workflow.stage(for: $0) == .ready }.count }
    private var activeProjects: Int { channelProjects.filter { [.editing, .rendered, .packaging].contains(workflow.stage(for: $0)) }.count }

    init(trends: TrendViewModel, apiKey: String) {
        self.trends = trends
        self.apiKey = apiKey
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                channelHero
                quickStrip
                continueSection
                trendFeed
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .task {
            if trends.items.isEmpty && !apiKey.isEmpty {
                trends.search(apiKey: apiKey, regionCode: app.regionCode, channel: app.channel)
            }
        }
    }

    private var channelHero: some View {
        HStack(alignment: .center, spacing: 18) {
            ChannelAvatar(title: app.channel.title, size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.channel.id == "local" ? "Dein Blackstock-Workspace" : app.channel.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    if app.channel.id != "local" {
                        Text("\(BlackstockFormat.compact(app.channel.subscriberCount)) Abonnenten")
                        Text("•")
                    }
                    Text("\(activeProjects) in Produktion")
                    Text("•")
                    Text("\(readyProjects) bereit")
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { app.selection = .trends } label: { Label("Trends entdecken", systemImage: "flame.fill") }
                .buttonStyle(.bordered)
            Button { app.createProject() } label: { Label("Video erstellen", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(.blackstockRed)
        }
    }

    private var quickStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickAction("Trends", "flame.fill", "\(trends.items.count) Signale", .trends)
                quickAction("Recherche", "scope", "Nischen prüfen", .research)
                quickAction("Ideen", "lightbulb.fill", "Formate ableiten", .ideas)
                quickAction("Projekte", "play.square.stack.fill", "\(channelProjects.count) im Kanal", .projects)
                quickAction("Analytics", "chart.xyaxis.line", "Leistung verstehen", .analytics)
            }
        }
    }

    @ViewBuilder private var continueSection: some View {
        if let project = channelProjects.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Weiterarbeiten").font(.title2.bold())
                    Spacer()
                    Button("Alle Projekte") { app.selection = .projects }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Button {
                    app.activeProject = project
                    app.selection = workflow.stage(for: project) == .ready ? .publish : .studio
                } label: {
                    HStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.86))
                            Image(systemName: project.targetFormat == .short ? "rectangle.portrait.fill" : "play.rectangle.fill")
                                .font(.system(size: 36)).foregroundStyle(.white)
                        }
                        .frame(width: 170, height: 96)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(project.title).font(.title3.bold()).lineLimit(2).multilineTextAlignment(.leading)
                            HStack(spacing: 7) {
                                Text(stageLabel(workflow.stage(for: project)))
                                Text("•")
                                Text(project.targetFormat == .short ? "Short" : "Longform")
                                Text("•")
                                Text(project.updatedAt, style: .relative)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if !project.workingHook.isEmpty { Text(project.workingHook).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(Color.blackstockRed)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                    .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var trendFeed: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aktuelle Signale").font(.title2.bold())
                    Text(app.channel.id == "local" ? "Was auf YouTube gerade auffällt" : "Für \(app.channel.title) eingeordnet")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if trends.isLoading { ProgressView().controlSize(.small) }
                Button("Alle anzeigen") { app.selection = .trends }.buttonStyle(.plain).foregroundStyle(.secondary)
            }

            if trends.items.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: apiKey.isEmpty ? "bolt.horizontal.circle" : "waveform.path.ecg")
                        .font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(apiKey.isEmpty ? "Live-Trends noch nicht aktiviert" : "Noch keine Signale geladen").font(.headline)
                        Text(apiKey.isEmpty ? "Verbinde öffentliche YouTube-Daten in den Einstellungen oder nutze die globale Suche." : (trends.errorMessage ?? "Starte eine Suche."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Öffnen") { app.selection = apiKey.isEmpty ? .settings : .trends }
                }
                .padding(18)
                .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 16))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(trends.items.prefix(10)) { trend in
                            Button { app.openTrend(trend) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .bottomTrailing) {
                                        AsyncImage(url: trend.video.thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(Color.primary.opacity(0.06)) }
                                            .frame(width: 244, height: 137).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        Text(BlackstockFormat.duration(trend.video.durationSeconds))
                                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
                                            .padding(7)
                                    }
                                    Text(trend.video.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading).frame(width: 244, alignment: .leading)
                                    Text("\(trend.video.channelTitle) · \(BlackstockFormat.compact(trend.video.viewCount)) Aufrufe")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    if let reason = trend.reasons.first {
                                        Label(reason.label, systemImage: reason.strength.symbol)
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 244, alignment: .leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func quickAction(_ title: String, _ icon: String, _ subtitle: String, _ section: AppState.Section) -> some View {
        Button { app.selection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(section == .trends ? Color.blackstockRed : Color.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(Color.primary.opacity(0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func stageLabel(_ stage: ProjectStage) -> String {
        switch stage {
        case .idea: return "Idee vorbereitet"
        case .editing: return "Im Studio"
        case .rendered: return "Gerendert"
        case .packaging: return "Packaging"
        case .ready: return "Bereit"
        }
    }
}
#endif
