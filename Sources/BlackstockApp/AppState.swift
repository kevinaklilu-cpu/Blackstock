#if os(macOS)
import SwiftUI
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
    @Published var channel = ChannelSnapshot(id: "local", title: "Mein Kanal", medianViews: 1, medianViewsPerHour: 1, recentTopics: [])
    func openTrend(_ trend: TrendSignal) { activeTrend = trend; selection = .trends }
    func startProject(from trend: TrendSignal) { activeProject = Project(title: trend.video.title, sourceVideoID: trend.video.id, targetFormat: trend.recommendedFormat); selection = .studio }
}
#endif
