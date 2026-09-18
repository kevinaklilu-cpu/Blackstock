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
    @Published var channelStrategies: [String: ChannelStrategy] { didSet { persistChannelStrategies() } }
    @Published var completedOnboardingChannelIDs: Set<String> { didSet { persistCompletedOnboarding() } }
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

        if let data = UserDefaults.standard.data(forKey: "blackstock.channelStrategies"),
           let saved = try? JSONDecoder().decode([String: ChannelStrategy].self, from: data) {
            channelStrategies = saved
        } else {
            channelStrategies = [:]
        }

        if let data = UserDefaults.standard.data(forKey: "blackstock.completedOnboardingChannels"),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedOnboardingChannelIDs = saved
        } else {
            completedOnboardingChannelIDs = []
        }
    }

    var hasAuthenticatedChannel: Bool {
        connectedChannels.contains { GoogleYouTubeAuth.isAuthenticated(channelID: $0.id) }
    }

    var shouldShowOnboarding: Bool {
        guard hasAuthenticatedChannel, channel.id != "local" else { return true }
        return channelStrategies[channel.id] == nil || !completedOnboardingChannelIDs.contains(channel.id)
    }

    var activeStrategy: ChannelStrategy? {
        channelStrategies[channel.id]
    }

    var projectsForActiveChannel: [Project] {
        guard channel.id != "local" else { return projects }
        return projects.filter { projectChannelIDs[$0.id.uuidString] == channel.id }
    }

    func channelID(for project: Project) -> String? {
        project.targetChannelID ?? projectChannelIDs[project.id.uuidString]
    }

    func channelTitle(for project: Project) -> String {
        guard let id = channelID(for: project) else { return "Kein Zielkanal" }
        return connectedChannels.first(where: { $0.id == id })?.title ?? (id == channel.id ? channel.title : "YouTube-Kanal")
    }

    func openTrend(_ trend: TrendSignal) { activeTrend = trend; selection = .trends }

    func createProject(title: String = "Neues Projekt") {
        let project = Project(
            title: title,
            targetChannelID: channel.id == "local" ? nil : channel.id,
            targetChannelTitle: channel.id == "local" ? nil : channel.title,
            titleVariants: [title],
            publishTitle: title
        )
        upsertProject(project)
        activeProject = project
        selection = .studio
    }

    func startProject(from trend: TrendSignal) {
        let project = Project(
            title: trend.video.title,
            targetChannelID: channel.id == "local" ? nil : channel.id,
            targetChannelTitle: channel.id == "local" ? nil : channel.title,
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
            targetChannelID: channel.id == "local" ? nil : channel.id,
            targetChannelTitle: channel.id == "local" ? nil : channel.title,
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
        if copy.targetChannelID == nil, channel.id != "local" {
            copy.targetChannelID = channel.id
            copy.targetChannelTitle = channel.title
        }
        if projectChannelIDs[copy.id.uuidString] == nil, let targetChannelID = copy.targetChannelID {
            projectChannelIDs[copy.id.uuidString] = targetChannelID
        }
        if let index = projects.firstIndex(where: { $0.id == copy.id }) { projects[index] = copy } else { projects.insert(copy, at: 0) }
        projects.sort { $0.updatedAt > $1.updatedAt }
        activeProject = copy
    }

    func moveProject(_ project: Project, to channelID: String) {
        guard let destination = connectedChannels.first(where: { $0.id == channelID }) else { return }
        var copy = project
        copy.targetChannelID = destination.id
        copy.targetChannelTitle = destination.title
        projectChannelIDs[project.id.uuidString] = destination.id
        upsertProject(copy)
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
            if let index = connectedChannels.firstIndex(where: { $0.id == snapshot.id }) {
                connectedChannels[index] = snapshot
            } else {
                connectedChannels.append(snapshot)
            }
        }
    }

    func completeFirstRun(
        channelID: String,
        primaryTopic: String,
        contentLanguage: String,
        now: Date = Date()
    ) {
        guard let selected = connectedChannels.first(where: { $0.id == channelID }) else { return }
        channel = selected

        let existingVersion = channelStrategies[channelID]?.version ?? 0
        let researchLanguages = contentLanguage == "de" ? ["de", "en"] : [contentLanguage]

        channelStrategies[channelID] = ChannelStrategy(
            channelId: channelID,
            primaryTopic: primaryTopic,
            topicDefinition: primaryTopic,
            contentPromise: primaryTopic,
            topicPillars: [],
            adjacentTopics: [],
            excludedTopics: [],
            defaultContentLanguage: contentLanguage,
            researchLanguages: researchLanguages,
            regionProfile: regionCode,
            strategicAudienceHypothesis: "",
            primaryObjectives: [.balanced],
            explorationPolicy: .init(),
            effectiveFrom: now,
            version: existingVersion + 1
        )
    }

    func finishFirstRun(channelID: String) {
        guard channelStrategies[channelID] != nil else { return }
        completedOnboardingChannelIDs.insert(channelID)
        selection = .dashboard
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
        if let data = try? JSONEncoder().encode(projectChannelIDs) {
            UserDefaults.standard.set(data, forKey: "blackstock.projectChannels")
        }
    }

    private func persistChannelStrategies() {
        if let data = try? JSONEncoder().encode(channelStrategies) {
            UserDefaults.standard.set(data, forKey: "blackstock.channelStrategies")
        }
    }

    private func persistCompletedOnboarding() {
        if let data = try? JSONEncoder().encode(completedOnboardingChannelIDs) {
            UserDefaults.standard.set(data, forKey: "blackstock.completedOnboardingChannels")
        }
    }
}
#endif
