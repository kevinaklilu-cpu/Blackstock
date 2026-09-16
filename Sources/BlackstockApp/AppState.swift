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
            case .dashboard: return "house.fill"
            case .trends: return "flame.fill"
            case .research: return "scope"
            case .ideas: return "lightbulb.fill"
            case .projects: return "play.square.stack.fill"
            case .studio: return "timeline.selection"
            case .publish: return "arrow.up.circle.fill"
            case .analytics: return "chart.xyaxis.line"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @Published var selection: Section? = .dashboard
    @Published var activeTrend: TrendSignal?
    @Published var activeProject: Project?
    @Published var projects: [Project] { didSet { persistProjects() } }
    @Published var connectedChannels: [ChannelSnapshot] { didSet { persistConnectedChannels() } }
    @Published var channel: ChannelSnapshot { didSet { persistChannel() } }
    @Published var regionCode: String { didSet { UserDefaults.standard.set(regionCode, forKey: "blackstock.region") } }
    @Published var onboardingSkipped: Bool { didSet { UserDefaults.standard.set(onboardingSkipped, forKey: "blackstock.onboardingSkipped") } }
    @Published private(set) var projectChannelIDs: [String: String] { didSet { persistProjectChannels() } }

    init() {
        let savedChannel: ChannelSnapshot
        if let data = UserDefaults.standard.data(forKey: "blackstock.channel"), let saved = try? JSONDecoder().decode(ChannelSnapshot.self, from: data) {
            savedChannel = saved
        } else {
            savedChannel = ChannelSnapshot(id: "local", title: "Mein Kanal")
        }
        channel = savedChannel

        if let data = UserDefaults.standard.data(forKey: "blackstock.connectedChannels"), let saved = try? JSONDecoder().decode([ChannelSnapshot].self, from: data) {
            connectedChannels = saved
        } else if savedChannel.id != "local" {
            connectedChannels = [savedChannel]
        } else {
            connectedChannels = []
        }

        if let data = UserDefaults.standard.data(forKey: "blackstock.projects"), let saved = try? JSONDecoder().decode([Project].self, from: data) {
            projects = saved.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            projects = []
        }

        if let data = UserDefaults.standard.data(forKey: "blackstock.projectChannels"), let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            projectChannelIDs = saved
        } else {
            projectChannelIDs = [:]
        }

        regionCode = UserDefaults.standard.string(forKey: "blackstock.region") ?? ""
        onboardingSkipped = UserDefaults.standard.bool(forKey: "blackstock.onboardingSkipped")
    }

    var hasAuthenticatedChannel: Bool {
        connectedChannels.contains { GoogleYouTubeAuth.isAuthenticated(channelID: $0.id) }
    }

    var shouldShowOnboarding: Bool { !hasAuthenticatedChannel && !onboardingSkipped }

    var projectsForActiveChannel: [Project] {
        guard channel.id != "local" else { return projects }
        return projects.filter { projectChannelIDs[$0.id.uuidString] == channel.id }
    }

    func channelID(for project: Project) -> String? { projectChannelIDs[project.id.uuidString] }

    func channelTitle(for project: Project) -> String {
        guard let id = channelID(for: project) else { return "Kein Zielkanal" }
        return connectedChannels.first(where: { $0.id == id })?.title ?? (id == channel.id ? channel.title : "YouTube-Kanal")
    }

    func openTrend(_ trend: TrendSignal) { activeTrend = trend; selection = .trends }

    func createProject(title: String = "Neues Projekt") {
        let project = Project(title: title, titleVariants: [title], publishTitle: title)
        upsertProject(project)
        activeProject = project
        selection = .studio
    }

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
        if projectChannelIDs[copy.id.uuidString] == nil, channel.id != "local" {
            projectChannelIDs[copy.id.uuidString] = channel.id
        }
        if let index = projects.firstIndex(where: { $0.id == copy.id }) { projects[index] = copy } else { projects.insert(copy, at: 0) }
        projects.sort { $0.updatedAt > $1.updatedAt }
        activeProject = copy
    }

    func moveProject(_ project: Project, to channelID: String) {
        projectChannelIDs[project.id.uuidString] = channelID
        persistProjectChannels()
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        projectChannelIDs.removeValue(forKey: project.id.uuidString)
        if activeProject?.id == project.id { activeProject = nil }
    }

    func setChannel(_ snapshot: ChannelSnapshot) {
        channel = snapshot
        if let index = connectedChannels.firstIndex(where: { $0.id == snapshot.id }) { connectedChannels[index] = snapshot }
    }

    func addConnectedChannels(_ snapshots: [ChannelSnapshot]) {
        for snapshot in snapshots {
            if let index = connectedChannels.firstIndex(where: { $0.id == snapshot.id }) { connectedChannels[index] = snapshot }
            else { connectedChannels.append(snapshot) }
        }
        if let first = snapshots.first { channel = first }
        onboardingSkipped = false
    }

    func selectChannel(id: String) {
        guard let selected = connectedChannels.first(where: { $0.id == id }) else { return }
        channel = selected
        activeProject = projectsForActiveChannel.first
    }

    func removeConnectedChannel(id: String) {
        connectedChannels.removeAll { $0.id == id }
        if channel.id == id { channel = connectedChannels.first ?? ChannelSnapshot(id: "local", title: "Mein Kanal") }
    }

    func continueWithoutAccount() { onboardingSkipped = true }
    func showOnboardingAgain() { onboardingSkipped = false }

    private func persistChannel() {
        if let data = try? JSONEncoder().encode(channel) { UserDefaults.standard.set(data, forKey: "blackstock.channel") }
    }

    private func persistConnectedChannels() {
        if let data = try? JSONEncoder().encode(connectedChannels) { UserDefaults.standard.set(data, forKey: "blackstock.connectedChannels") }
    }

    private func persistProjects() {
        if let data = try? JSONEncoder().encode(projects) { UserDefaults.standard.set(data, forKey: "blackstock.projects") }
    }

    private func persistProjectChannels() {
        if let data = try? JSONEncoder().encode(projectChannelIDs) { UserDefaults.standard.set(data, forKey: "blackstock.projectChannels") }
    }
}
#endif
