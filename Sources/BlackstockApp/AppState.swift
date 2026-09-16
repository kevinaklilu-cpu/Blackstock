#if os(macOS)
import SwiftUI
import Foundation
import BlackstockCore

@MainActor final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Übersicht", trends = "Trends", research = "Recherche", ideas = "Ideen", projects = "Projekte", studio = "Studio", publish = "Veröffentlichen", analytics = "Analytics", settings = "Einstellungen"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .trends: return "waveform.path.ecg"
            case .research: return "scope"
            case .ideas: return "lightbulb"
            case .projects: return "square.stack.3d.up"
            case .studio: return "timeline.selection"
            case .publish: return "arrow.up.circle"
            case .analytics: return "chart.xyaxis.line"
            case .settings: return "gearshape"
            }
        }
    }

    @Published var selection: Section? = .dashboard
    @Published var activeTrend: TrendSignal?
    @Published var activeProject: Project?
    @Published var projects: [Project] { didSet { persistProjects() } }
    @Published var channel: ChannelSnapshot { didSet { persistChannel() } }
    @Published var regionCode: String { didSet { UserDefaults.standard.set(regionCode, forKey: "blackstock.region") } }

    init() {
        if let data = UserDefaults.standard.data(forKey: "blackstock.channel"), let saved = try? JSONDecoder().decode(ChannelSnapshot.self, from: data) { channel = saved } else { channel = ChannelSnapshot(id: "local", title: "Mein Kanal") }
        if let data = UserDefaults.standard.data(forKey: "blackstock.projects"), let saved = try? JSONDecoder().decode([Project].self, from: data) { projects = saved.sorted { $0.updatedAt > $1.updatedAt } } else { projects = [] }
        regionCode = UserDefaults.standard.string(forKey: "blackstock.region") ?? ""
    }

    func openTrend(_ trend: TrendSignal) { activeTrend = trend; selection = .trends }

    func startProject(from trend: TrendSignal) {
        let project = Project(
            title: trend.video.title,
            sourceVideoID: trend.video.id,
            sourceEvidenceIDs: [trend.video.id],
            targetFormat: trend.recommendedFormat,
            workingHook: trend.reasons.first?.label ?? "",
            titleVariants: [trend.video.title],
            publishTitle: trend.video.title
        )
        upsertProject(project)
        activeProject = project
        selection = .studio
    }

    func startProject(from idea: ContentIdea) {
        let project = Project(
            title: idea.workingTitle,
            sourceVideoID: idea.sourceVideoIDs.first,
            sourceEvidenceIDs: idea.sourceVideoIDs,
            targetFormat: idea.recommendedFormat,
            workingHook: idea.evidence.first ?? "",
            titleVariants: [idea.workingTitle],
            publishTitle: idea.workingTitle
        )
        upsertProject(project)
        activeProject = project
        selection = .studio
    }

    func openProject(_ project: Project) { activeProject = project; selection = .studio }

    func upsertProject(_ project: Project) {
        var copy = project
        copy.updatedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == copy.id }) { projects[index] = copy } else { projects.insert(copy, at: 0) }
        projects.sort { $0.updatedAt > $1.updatedAt }
        activeProject = copy
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id { activeProject = nil }
    }

    func setChannel(_ snapshot: ChannelSnapshot) { channel = snapshot }

    private func persistChannel() {
        if let data = try? JSONEncoder().encode(channel) { UserDefaults.standard.set(data, forKey: "blackstock.channel") }
    }

    private func persistProjects() {
        if let data = try? JSONEncoder().encode(projects) { UserDefaults.standard.set(data, forKey: "blackstock.projects") }
    }
}
#endif
