#if os(macOS)
import SwiftUI
import BlackstockCore

@main
struct BlackstockApp: App {
    @StateObject private var session = BlackstockSession()
    @State private var commandPaletteRequest = 0

    var body: some Scene {
        WindowGroup {
            Group {
                if session.onboardingComplete {
                    WorkspaceShell(
                        session: session,
                        commandPaletteRequest: commandPaletteRequest
                    )
                } else {
                    FirstRunView(session: session)
                }
            }
            .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Blackstock") {
                Button("Befehlspalette …") {
                    commandPaletteRequest += 1
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!session.onboardingComplete)
            }
        }
    }
}

private struct WorkspaceShell: View {
    @ObservedObject var session: BlackstockSession
    let commandPaletteRequest: Int

    @State private var selection = "Übersicht"
    @State private var showCommandPalette = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Übersicht", systemImage: "rectangle.grid.2x2")
                    .tag("Übersicht")
                if session.activeProject != nil {
                    Label("Studio", systemImage: "film.stack")
                        .tag("Studio")
                }
                Label("Einstellungen", systemImage: "gearshape")
                    .tag("Einstellungen")
            }
            .navigationTitle("Blackstock")
        } detail: {
            switch selection {
            case "Studio":
                if let project = session.activeProject {
                    StudioView(
                        project: project,
                        opportunitySource: session.activeOpportunitySource
                    )
                } else {
                    OverviewView(session: session)
                }
            case "Einstellungen":
                SettingsView(session: session)
            default:
                OverviewView(session: session)
            }
        }
        .onChange(of: commandPaletteRequest) { _ in
            showCommandPalette = true
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                currentSelection: selection,
                hasActiveProject: session.activeProject != nil,
                onNavigate: { destination in
                    selection = destination
                    showCommandPalette = false
                },
                onRestartFirstRun: {
                    showCommandPalette = false
                    session.resetFirstRun()
                }
            )
        }
    }
}

private struct CommandPaletteView: View {
    let currentSelection: String
    let hasActiveProject: Bool
    let onNavigate: (String) -> Void
    let onRestartFirstRun: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Command: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImage: String
        let destination: String?
        let isDestructive: Bool
    }

    private var commands: [Command] {
        var result: [Command] = [
            .init(
                id: "overview",
                title: "Übersicht öffnen",
                subtitle: "Zum aktuellen Blackstock-Workspace",
                systemImage: "rectangle.grid.2x2",
                destination: "Übersicht",
                isDestructive: false
            )
        ]

        if hasActiveProject {
            result.append(
                .init(
                    id: "studio",
                    title: "Studio öffnen",
                    subtitle: "Aktives Projekt visuell bearbeiten",
                    systemImage: "film.stack",
                    destination: "Studio",
                    isDestructive: false
                )
            )
        }

        result.append(contentsOf: [
            .init(
                id: "settings",
                title: "Einstellungen öffnen",
                subtitle: "Google-/YouTube- und App-Einstellungen",
                systemImage: "gearshape",
                destination: "Einstellungen",
                isDestructive: false
            ),
            .init(
                id: "restart-first-run",
                title: "First Run erneut starten",
                subtitle: "Workspace-Auswahl und Einrichtung erneut durchlaufen",
                systemImage: "arrow.counterclockwise",
                destination: nil,
                isDestructive: true
            )
        ])
        return result
    }

    private var filteredCommands: [Command] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return commands }
        return commands.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
            || $0.subtitle.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("Befehl suchen …", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding(16)

            Divider()

            List(filteredCommands) { command in
                Button {
                    if command.id == "restart-first-run" {
                        onRestartFirstRun()
                    } else if let destination = command.destination {
                        onNavigate(destination)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: command.systemImage)
                            .frame(width: 22)
                            .foregroundStyle(
                                command.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.title)
                                .font(.headline)
                            Text(command.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if command.destination == currentSelection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .frame(width: 560, height: 360)
        .onExitCommand {
            dismiss()
        }
    }
}

private struct OverviewView: View {
    @ObservedObject var session: BlackstockSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Blackstock")
                .font(.largeTitle.bold())
            Text("Creator Intelligence, Research, Production, Publishing & Growth OS")
                .font(.title3)
                .foregroundStyle(.secondary)

            GroupBox("Produktstatus") {
                HStack {
                    Image(systemName: "hammer.fill")
                    Text("NOCH NICHT MARKTREIF")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Text("Der First-Run nutzt reale Google-/YouTube-Autorisierung. Weitere Produktflächen bleiben unsichtbar, bis ihre Capability-Gates bestehen.")
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
            Text("Einstellungen")
                .font(.largeTitle.bold())

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
