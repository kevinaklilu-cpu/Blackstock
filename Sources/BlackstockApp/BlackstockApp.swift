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
                        session: session,
                        project: project,
                        opportunitySource: session.activeOpportunitySource,
                        contentLanguage: session.contentLanguage
                    )
                } else {
                    OverviewView(
                        session: session,
                        onOpenStudio: { selection = "Studio" }
                    )
                }
            case "Einstellungen":
                SettingsView(session: session)
            default:
                OverviewView(
                    session: session,
                    onOpenStudio: { selection = "Studio" }
                )
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
                subtitle: "Zum aktuellen Blackstock-Arbeitsbereich",
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
                title: "Ersteinrichtung erneut starten",
                subtitle: "Arbeitsbereich-Auswahl und Einrichtung erneut durchlaufen",
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
    let onOpenStudio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Blackstock")
                .font(.largeTitle.bold())
            Text("Creator-System für Recherche, Produktion, Veröffentlichung und Wachstum")
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

            if let project = session.activeProject {
                let guidance = project.stage.journeyGuidance

                GroupBox("Aktiver Projektpfad") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.headline)
                                Text(guidance.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(
                                "Schritt \(project.stage.canonicalProgressPosition) von \(BlackstockStage.canonicalProgressCount)"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }

                        ProgressView(
                            value: Double(
                                project.stage.canonicalProgressPosition
                            ),
                            total: Double(
                                BlackstockStage.canonicalProgressCount
                            )
                        )
                        .accessibilityLabel("Fortschritt im kanonischen Blackstock-Projektpfad")
                        .accessibilityValue(
                            "Schritt \(project.stage.canonicalProgressPosition) von \(BlackstockStage.canonicalProgressCount)"
                        )

                        Text(guidance.purpose)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nächster sinnvoller Schritt")
                                .font(.caption.weight(.semibold))
                            Text(guidance.nextAction)
                                .font(.callout)
                        }

                        if guidance.recommendedSurface == .studio {
                            Button {
                                onOpenStudio()
                            } label: {
                                Label(
                                    "Im Studio fortfahren",
                                    systemImage: "arrow.right.circle.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        } else if guidance.recommendedSurface == .overview {
                            Label(
                                "Du bist bereits im passenden Bereich Veröffentlicht / Lernen.",
                                systemImage: "checkmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
            }

            if let project = session.activeProject,
               project.stage == .published,
               let record = session.loadPublishedRecord(
                    projectID: project.id
               ) {
                growthLoopCard(
                    project: project,
                    record: record
                )
            }

            Spacer()
        }
        .padding(28)
    }

    @ViewBuilder
    private func growthLoopCard(
        project: BlackstockProject,
        record: PublishedVideoRecord
    ) -> some View {
        GroupBox("Veröffentlichung → Analytics → Lernen") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.title)
                            .font(.headline)
                        Text("YouTube Video-ID: \(record.youtubeVideoID)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Spacer()
                }

                let due = GrowthObservationPlanner().duePlans(
                    for: record,
                    now: Date()
                )
                let next = GrowthObservationPlanner().nextDueAt(
                    for: record,
                    now: Date()
                )

                if session.analyticsAuthorizedChannelID
                    == project.targetChannelID {
                    HStack {
                        Button {
                            Task {
                                await session.collectDueGrowthObservations()
                            }
                        } label: {
                            HStack {
                                if session.isCollectingAnalytics {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    session.isCollectingAnalytics
                                        ? "Analytics werden aktualisiert …"
                                        : "Fällige Analytics aktualisieren",
                                    systemImage: "chart.line.uptrend.xyaxis"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            session.isCollectingAnalytics
                            || due.isEmpty
                        )

                        if due.isEmpty {
                            Text("Aktuell kein Beobachtungsfenster fällig.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button {
                        Task {
                            await session.authorizeAnalytics()
                        }
                    } label: {
                        HStack {
                            if session.isAuthorizingAnalytics {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                session.isAuthorizingAnalytics
                                    ? "Analytics-Autorisierung läuft …"
                                    : "YouTube Analytics aktivieren",
                                systemImage: "key"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.isAuthorizingAnalytics)
                }

                if !due.isEmpty {
                    Text(
                        "Fällig: "
                        + due.map { $0.window.germanTitle }
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let next {
                    Text(
                        "Nächster geplanter Check: "
                        + next.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let learning = session.latestGrowthLearning {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Belegte Lernfakten")
                            .font(.headline)
                        ForEach(
                            Array(learning.facts.enumerated()),
                            id: \.offset
                        ) { _, fact in
                            Label(fact, systemImage: "circle.fill")
                                .font(.caption)
                        }
                        if let question = learning.nextQuestion {
                            Text(question)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !record.observations.isEmpty {
                    let learning = GrowthLearningEngine()
                        .summarize(record)
                    if let learning {
                        Divider()
                        ForEach(
                            Array(learning.facts.enumerated()),
                            id: \.offset
                        ) { _, fact in
                            Text("• " + fact)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("Noch keine vollständige YouTube-Analytics-Beobachtung gespeichert. Verzögerte Daten werden nicht als Nullwerte interpretiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YouTube-Kommentare")
                                .font(.headline)
                            Text("Nur lesen · Hauptkommentare")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                await session.loadPublishedComments(
                                    project: project,
                                    record: record
                                )
                            }
                        } label: {
                            HStack {
                                if session.isLoadingComments {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    session.isLoadingComments
                                        ? "Kommentare werden geladen …"
                                        : "Kommentare aktualisieren",
                                    systemImage: "bubble.left.and.bubble.right"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(session.isLoadingComments)
                    }

                    if session.latestCommentsVideoID == record.youtubeVideoID,
                       let page = session.latestCommentPage {
                        if page.threads.isEmpty {
                            Text("YouTube liefert aktuell keine veröffentlichten Hauptkommentare für dieses Video.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(page.threads.prefix(8)) { thread in
                                HStack(alignment: .top, spacing: 10) {
                                    AsyncImage(
                                        url: thread.topLevelComment
                                            .authorProfileImageURL
                                    ) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.primary.opacity(0.08))
                                    }
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(
                                                thread.topLevelComment
                                                    .authorDisplayName
                                            )
                                            .font(.caption.weight(.semibold))
                                            Spacer()
                                            if let publishedAt = thread
                                                .topLevelComment.publishedAt {
                                                Text(
                                                    publishedAt.formatted(
                                                        date: .abbreviated,
                                                        time: .shortened
                                                    )
                                                )
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            }
                                        }

                                        Text(
                                            thread.topLevelComment.textDisplay
                                        )
                                        .font(.caption)
                                        .textSelection(.enabled)

                                        HStack(spacing: 10) {
                                            if let likes = thread
                                                .topLevelComment.likeCount {
                                                Label(
                                                    "\(likes)",
                                                    systemImage: "hand.thumbsup"
                                                )
                                            }
                                            if let replies = thread
                                                .totalReplyCount {
                                                Label(
                                                    "\(replies) Antworten",
                                                    systemImage: "arrowshape.turn.up.left"
                                                )
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            if page.threads.count > 8
                                || page.nextPageToken != nil {
                                Text("Weitere Kommentare sind bei YouTube vorhanden; diese Ansicht zeigt bewusst nur einen begrenzten Ausschnitt.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(
                                "Abruf: "
                                + page.retrievedAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                                + " · YouTube Data API · Sortierung: Neueste. "
                                + "Die Antwortzahl stammt von YouTube; Antworten selbst werden hier noch nicht vollständig geladen."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Noch keine Kommentare für dieses veröffentlichte Video abgerufen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = session.errorMessage {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

}

private struct SettingsView: View {
    @ObservedObject var session: BlackstockSession
    @State private var showCredentialRemovalConfirmation = false
    @State private var credentialStatusMessage: String?
    @State private var showLocalDataRemovalConfirmation = false
    @State private var localDataStatusMessage: String?
    @State private var isCheckingForUpdates = false
    @State private var isDownloadingUpdatePackage = false
    @State private var availableUpdateManifest: BlackstockUpdateManifest?
    @State private var verifiedUpdatePackageURL: URL?
    @State private var updateStatusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Einstellungen")
                .font(.largeTitle.bold())

            GroupBox("Google / YouTube") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("OAuth-Konfiguration: \(session.oauthConfigurationSource)")
                    Text("Entwickler-Secrets und API-Key-Felder werden normalen Nutzern nicht angeboten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Button(
                        "Lokale YouTube-Anmeldung entfernen",
                        role: .destructive
                    ) {
                        showCredentialRemovalConfirmation = true
                    }

                    Text("Entfernt lokal gespeicherte YouTube-Zugriffs-, Refresh- und Scope-Daten aus dem macOS-Keychain. Die OAuth-Client-Konfiguration und deine Projektdateien bleiben erhalten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let credentialStatusMessage {
                        Text(credentialStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            .confirmationDialog(
                "Lokale YouTube-Anmeldung entfernen?",
                isPresented: $showCredentialRemovalConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "Anmeldedaten von diesem Mac entfernen",
                    role: .destructive
                ) {
                    do {
                        let removed = try session.removeLocalGoogleCredentials()
                        credentialStatusMessage = removed > 0
                            ? "\(removed) lokale Keychain-Einträge wurden entfernt."
                            : "Es waren keine lokalen YouTube-Anmeldedaten gespeichert."
                    } catch {
                        credentialStatusMessage = "Anmeldedaten konnten nicht vollständig entfernt werden: \(error.localizedDescription)"
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Aktion meldet Blackstock lokal ab. Sie widerruft keine Berechtigung im Google-Konto und löscht keine Projektdateien.")
            }

            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Task {
                            isCheckingForUpdates = true
                            defer { isCheckingForUpdates = false }

                            do {
                                switch try await BlackstockUpdateChecker().check() {
                                case .notConfigured:
                                    availableUpdateManifest = nil
                                    verifiedUpdatePackageURL = nil
                                    updateStatusMessage = "Update-Prüfung ist in diesem Build noch nicht konfiguriert."
                                case .upToDate:
                                    availableUpdateManifest = nil
                                    verifiedUpdatePackageURL = nil
                                    updateStatusMessage = "Blackstock ist auf dem aktuellen Stand."
                                case .updateAvailable(let manifest):
                                    availableUpdateManifest = manifest
                                    verifiedUpdatePackageURL = nil
                                    updateStatusMessage = "Update verfügbar: Version \(manifest.version), Build \(manifest.build). Das Paket wird erst nach ausdrücklicher Aktion geladen und gegen den signierten SHA-256 geprüft."
                                }
                            } catch {
                                if let localized = error as? LocalizedError,
                                   let description = localized.errorDescription {
                                    updateStatusMessage = "Update-Prüfung fehlgeschlagen: \(description)"
                                } else {
                                    updateStatusMessage = "Update-Prüfung fehlgeschlagen: \(error.localizedDescription)"
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if isCheckingForUpdates {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                isCheckingForUpdates
                                    ? "Updates werden geprüft …"
                                    : "Nach Updates suchen",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                    }
                    .disabled(isCheckingForUpdates || isDownloadingUpdatePackage)

                    if let manifest = availableUpdateManifest {
                        Button {
                            Task {
                                isDownloadingUpdatePackage = true
                                defer { isDownloadingUpdatePackage = false }

                                do {
                                    let url = try await BlackstockUpdatePackageDownloader()
                                        .downloadAndVerify(manifest: manifest)
                                    verifiedUpdatePackageURL = url
                                    updateStatusMessage = "Update-Paket wurde geladen und per SHA-256 verifiziert. Es wird nicht automatisch installiert."
                                } catch {
                                    verifiedUpdatePackageURL = nil
                                    if let localized = error as? LocalizedError,
                                       let description = localized.errorDescription {
                                        updateStatusMessage = "Update-Paket wurde verworfen: \(description)"
                                    } else {
                                        updateStatusMessage = "Update-Paket wurde verworfen: \(error.localizedDescription)"
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                if isDownloadingUpdatePackage {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    isDownloadingUpdatePackage
                                        ? "Update-Paket wird geprüft …"
                                        : "Update-Paket laden und prüfen",
                                    systemImage: "checkmark.shield"
                                )
                            }
                        }
                        .disabled(isCheckingForUpdates || isDownloadingUpdatePackage)
                    }

                    Text("Blackstock akzeptiert nur HTTPS-Manifeste mit gültiger Ed25519-Signatur. Ein geladenes Paket muss zusätzlich exakt dem signierten SHA-256 entsprechen. Installation erfolgt nicht automatisch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let updateStatusMessage {
                        Text(updateStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let verifiedUpdatePackageURL {
                        Text("Verifiziertes Paket: \(verifiedUpdatePackageURL.path)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            GroupBox("Datenschutz & lokale Daten") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blackstock speichert Projekt-, Wachstums- und Arbeitsbereichsdaten lokal im Benutzerprofil. Google-/YouTube-Zugangsdaten liegen im macOS-Keychain.")

                    Button(
                        "Alle lokalen Blackstock-Daten löschen",
                        role: .destructive
                    ) {
                        showLocalDataRemovalConfirmation = true
                    }

                    Text("Löscht lokale Projekte, Renders, Captions, Thumbnails, Growth-Daten, Blackstock-Einstellungen, gespeicherte Google-/YouTube-Anmeldedaten und eine importierte OAuth-Client-Konfiguration von diesem Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let localDataStatusMessage {
                        Text(localDataStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            .confirmationDialog(
                "Alle lokalen Blackstock-Daten löschen?",
                isPresented: $showLocalDataRemovalConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "Lokale Daten endgültig löschen",
                    role: .destructive
                ) {
                    let summary = session.removeAllLocalBlackstockData()
                    if summary.isComplete {
                        localDataStatusMessage = nil
                    } else {
                        localDataStatusMessage = summary.failures.joined(
                            separator: " "
                        )
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Aktion ist lokal endgültig. Sie löscht keine bereits veröffentlichten YouTube-Videos und widerruft keine Berechtigungen direkt im Google-Konto.")
            }

            Button("Ersteinrichtung erneut starten", role: .destructive) {
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
