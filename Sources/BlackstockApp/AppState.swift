#if os(macOS)
import SwiftUI
import Foundation
import BlackstockCore

@MainActor final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "Übersicht", trends = "Trends", studio = "Studio", publish = "Veröffentlichen", analytics = "Analytics", settings = "Einstellungen"
        var id: String { rawValue }
        var icon: String { switch self { case .dashboard: return "square.grid.2x2"; case .trends: return "waveform.path.ecg"; case .studio: return "timeline.selection"; case .publish: return "arrow.up.circle"; case .analytics: return "chart.xyaxis.line"; case .settings: return "gearshape" } }
    }

    @Published var selection: Section? = .dashboard
    @Published var activeTrend: TrendSignal?
    @Published var activeProject: Project?
    @Published var channel: ChannelSnapshot { didSet { persistChannel() } }
    @Published var regionCode: String { didSet { UserDefaults.standard.set(regionCode, forKey: "blackstock.region") } }

    init() {
        if let data = UserDefaults.standard.data(forKey: "blackstock.channel"), let saved = try? JSONDecoder().decode(ChannelSnapshot.self, from: data) { channel = saved }
        else { channel = ChannelSnapshot(id: "local", title: "Mein Kanal", medianViews: 1, medianViewsPerHour: 1, recentTopics: []) }
        regionCode = UserDefaults.standard.string(forKey: "blackstock.region") ?? ""
    }

    func openTrend(_ trend: TrendSignal) { activeTrend = trend; selection = .trends }
    func startProject(from trend: TrendSignal) { activeProject = Project(title: trend.video.title, sourceVideoID: trend.video.id, targetFormat: trend.recommendedFormat); selection = .studio }
    func setChannel(_ snapshot: ChannelSnapshot) { channel = snapshot }

    private func persistChannel() { if let data = try? JSONEncoder().encode(channel) { UserDefaults.standard.set(data, forKey: "blackstock.channel") } }
}
#endif
