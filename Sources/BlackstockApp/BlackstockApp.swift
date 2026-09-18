#if os(macOS)
import SwiftUI
import BlackstockCore

@main struct BlackstockApp: App {
    var body: some Scene {
        WindowGroup { RootView().frame(minWidth: 1040, minHeight: 700) }
        .windowStyle(.titleBar)
    }
}

private struct RootView: View {
    @State private var selected = "Übersicht"
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Label("Übersicht", systemImage: "rectangle.grid.2x2").tag("Übersicht")
                Label("Einstellungen", systemImage: "gearshape").tag("Einstellungen")
            }.navigationTitle("Blackstock")
        } detail: {
            if selected == "Einstellungen" { SettingsView() } else { OverviewView() }
        }
    }
}

private struct OverviewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Blackstock").font(.largeTitle.bold())
            Text("Creator Intelligence, Research, Production, Publishing & Growth OS").font(.title3).foregroundStyle(.secondary)
            GroupBox("Produktstatus") {
                HStack { Image(systemName: "hammer.fill"); Text("NOCH NICHT MARKTREIF").fontWeight(.semibold); Spacer() }.padding(.vertical, 6)
            }
            Text("Funktionen erscheinen erst, wenn die jeweilige Capability real implementiert, autorisiert, qualitätsgeprüft und getestet ist.").foregroundStyle(.secondary)
            Spacer()
        }.padding(28)
    }
}

private struct SettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Einstellungen").font(.largeTitle.bold())
            Text("Die neue kanonische Implementierung wird capability-basiert aufgebaut. Entwickler-Secrets und API-Key-Felder gehören nicht in die normale Produktoberfläche.").foregroundStyle(.secondary)
            Spacer()
        }.padding(28)
    }
}
#else
import Foundation
@main struct BlackstockCLI { static func main() { print("Blackstock requires macOS 13 or later.") } }
#endif