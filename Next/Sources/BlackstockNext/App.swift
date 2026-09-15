import SwiftUI

@main
struct BlackstockNextApp: App {
    var body: some Scene {
        WindowGroup {
            StudioRootView()
                .frame(minWidth: 1180, minHeight: 760)
        }
        .commands {
            CommandMenu("Blackstock") {
                Button("Schneiden") {
                    NotificationCenter.default.post(name: .blackstockOpenCut, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let blackstockOpenCut = Notification.Name("blackstock.open-cut")
}
