#if os(macOS)
import SwiftUI
import AppKit
import BlackstockCore

@main struct Blackstock: App {
    @StateObject private var appState = AppState()
    @StateObject private var trends = TrendViewModel()
    @StateObject private var auth = GoogleYouTubeAuth()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.shouldShowOnboarding {
                    OnboardingView()
                } else {
                    CreatorShellView(trends: trends)
                }
            }
            .environmentObject(appState)
            .environmentObject(auth)
            .frame(minWidth: 1180, minHeight: 760)
            .onAppear { NSApplication.shared.applicationIconImage = BrandAppIcon.make() }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neues Projekt") { appState.createProject() }
                    .keyboardShortcut("n")
            }
            CommandMenu("Blackstock") {
                Button("Übersicht") { appState.selection = .dashboard }.keyboardShortcut("0", modifiers: [.command])
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
