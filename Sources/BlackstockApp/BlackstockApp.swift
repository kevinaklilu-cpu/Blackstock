#if os(macOS)
import SwiftUI
import BlackstockCore

@main struct Blackstock: App {
    @StateObject private var appState = AppState()
    @StateObject private var trends = TrendViewModel()
    @State private var apiKey = Keychain.read("youtube-data-api-key")
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(AppState.Section.allCases, selection: $appState.selection) { section in Label(section.rawValue, systemImage: section.icon).tag(section) }.navigationTitle("Blackstock").frame(minWidth: 190)
            } detail: {
                Group {
                    switch appState.selection ?? .dashboard {
                    case .dashboard: DashboardView(trends: trends, apiKey: apiKey)
                    case .trends: TrendsView(model: trends, apiKey: apiKey)
                    case .ideas: IdeasView(trends: trends)
                    case .projects: ProjectsView()
                    case .studio: StudioView()
                    case .publish: PublishView()
                    case .analytics: AnalyticsView()
                    case .settings: SettingsView(apiKey: $apiKey)
                    }
                }.environmentObject(appState)
            }.frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .newItem) { Button("Neues Projekt") { let project = Project(title: "Neues Projekt", titleVariants: ["Neues Projekt"]); appState.upsertProject(project); appState.activeProject = project; appState.selection = .studio }.keyboardShortcut("n") } }
    }
}
#else
import Foundation
@main struct BlackstockCLI { static func main() { print("Blackstock requires macOS 13 or later.") } }
#endif
