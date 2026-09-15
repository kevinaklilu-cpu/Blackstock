import SwiftUI

@main
struct BlackstockMarketReadyApp: App {
    @StateObject private var state = BlackstockState()

    var body: some Scene {
        WindowGroup {
            BlackstockRootView(state: state)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .newItem) { } }
    }
}
