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
                List(AppState.Section.allCases, selection: $appState.selection) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
                .navigationTitle("Blackstock")
                .frame(minWidth: 200)
            } detail: {
                Group {
                    switch appState.selection ?? .dashboard {
                    case .dashboard: DashboardView(trends: trends, apiKey: apiKey)
                    case .trends: TrendsView(model: trends, apiKey: apiKey)
                    case .research: ResearchView(trends: trends)
                    case .ideas: IdeasView(trends: trends)
                    case .projects: ProjectsView()
                    case .studio: StudioView()
                    case .publish: PublishView()
                    case .analytics: AnalyticsView()
                    case .settings: SettingsView(apiKey: $apiKey)
                    }
                }
                .environmentObject(appState)
            }
            .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neues Projekt") {
                    let project = Project(title: "Neues Projekt", titleVariants: ["Neues Projekt"], publishTitle: "Neues Projekt")
                    appState.upsertProject(project)
                    appState.activeProject = project
                    appState.selection = .studio
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Blackstock") {
                Button("Trends") { appState.selection = .trends }.keyboardShortcut("1", modifiers: [.command])
                Button("Recherche") { appState.selection = .research }.keyboardShortcut("2", modifiers: [.command])
                Button("Studio") { appState.selection = .studio }.keyboardShortcut("3", modifiers: [.command])
                Button("Veröffentlichen") { appState.selection = .publish }.keyboardShortcut("4", modifiers: [.command])
            }
        }
    }
}
#else
import Foundation
@main struct BlackstockCLI { static func main() { print("Blackstock requires macOS 13 or later.") } }
#endif
