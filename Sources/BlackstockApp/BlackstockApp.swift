#if os(macOS)
import SwiftUI
import BlackstockCore

@main
struct BlackstockApp: App {
    @StateObject private var session = BlackstockSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.onboardingComplete {
                    WorkspaceShell(session: session)
                } else {
                    FirstRunView(session: session)
                }
            }
            .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Blackstock") {
                Button("Befehlspalette") { }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(true)
            }
        }
    }
}

private struct WorkspaceShell: View {
    @ObservedObject var session: BlackstockSession
    @State private var selection = "Übersicht"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Übersicht", systemImage: "rectangle.grid.2x2").tag("Übersicht")
                Label("Einstellungen", systemImage: "gearshape").tag("Einstellungen")
            }
            .navigationTitle("Blackstock")
        } detail: {
            switch selection {
            case "Einstellungen":
                SettingsView(session: session)
            default:
                OverviewView(session: session)
            }
        }
    }



private struct OverviewView: View {
    @ObservedObject var session: BlackstockSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Blackstock").font(.largeTitle.bold())
            Text("Creator Intelligence, Research, Production, Publishing & Growth OS")
                .font(.title3)
                .foregroundStyle(.secondary)

            GroupBox("Produktstatus") {
                HStack {
                    Image(systemName: "hammer.fill")
                    Text("NOCH NICHT MARKTREIF").fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Text("Der First-Run nutzt reale Google-/YouTube-Autorisierung. Weitere Produktflächen bleiben unsichtbar oder klar gesperrt, bis ihre Capability-Gates bestehen.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
    }
}

private struct SettingsView: View {
    @ObservedObject var session: BlackstockSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Einstellungen").font(.largeTitle.bold())

            GroupBox("Google / YouTube") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OAuth-Konfiguration: \(session.oauthConfigurationSource)")
                    Text("Entwickler-Secrets und API-Key-Felder werden normalen Nutzern nicht angeboten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            Button("First Run erneut starten", role: .destructive) {
                session.resetFirstRun()
            }

            Spacer()
        }
        .padding(28)
    }
}
#else
import Foundation

@main
struct BlackstockCLI {
    static func main() {
        print("Blackstock requires macOS 13 or later.")
    }
}
#endif
