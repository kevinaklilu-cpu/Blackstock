#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
            VStack(spacing: 0) {
                HStack {
                    BlackstockWordmark(
                        markWidth: 34,
                        markHeight: 24,
                        font: .headline
                    )
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                List(selection: $selection) {
                    Label(
                        "Übersicht",
                        systemImage: "rectangle.grid.2x2"
                    )
                    .tag("Übersicht")

                    Label(
                        "Entdecken",
                        systemImage: "sparkle.magnifyingglass"
                    )
                    .tag("Chancen")

                    Label(
                        "Projekte",
                        systemImage: "tray.full"
                    )
                    .tag("Projekte")

                    if session.activeProject?.stage
                        .journeyGuidance
                        .recommendedSurface == .studio {
                        Label(
                            "Editor",
                            systemImage: "film.stack"
                        )
                        .tag("Studio")
                    }

                    Label(
                        "Einstellungen",
                        systemImage: "gearshape"
                    )
                    .tag("Einstellungen")
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(
                min: 190,
                ideal: 220,
                max: 260
            )
        } detail: {
            switch selection {
            case "Chancen":
                OpportunityWorkspaceView(
                    session: session,
                    onProjectCreated: {
                        selection = "Übersicht"
                    }
                )
            case "Projekte":
                ProjectLibraryView(
                    session: session,
                    onOpenProject: { project in
                        guard session.selectProject(project.id)
                        else {
                            return
                        }
                        selection =
                            project.stage.journeyGuidance
                                .recommendedSurface == .studio
                            ? "Studio"
                            : "Übersicht"
                    },
                    onFindOpportunity: {
                        selection = "Chancen"
                    }
                )
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
                hasActiveProject: session.activeProject?.stage
                    .journeyGuidance.recommendedSurface == .studio,
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
    @FocusState private var queryFocused: Bool

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
            ),
            .init(
                id: "opportunities",
                title: "Entdecken",
                subtitle: "Videos und Themen finden",
                systemImage: "sparkle.magnifyingglass",
                destination: "Chancen",
                isDestructive: false
            ),
            .init(
                id: "projects",
                title: "Projekte",
                subtitle: "Projekte öffnen",
                systemImage: "tray.full",
                destination: "Projekte",
                isDestructive: false
            )
        ]

        if hasActiveProject {
            result.append(
                .init(
                    id: "studio",
                    title: "Editor",
                    subtitle: "Aktives Projekt bearbeiten",
                    systemImage: "film.stack",
                    destination: "Studio",
                    isDestructive: false
                )
            )
        }

        result.append(contentsOf: [
            .init(
                id: "settings",
                title: "Einstellungen",
                subtitle: "Google, YouTube und App",
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
                    .focused($queryFocused)
                    .accessibilityLabel("Befehl suchen")
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
        .task {
            queryFocused = true
        }
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
            Text("Übersicht")
                .font(.largeTitle.bold())
            Text("Deine Projekte, nächsten Schritte und Ergebnisse")
                .font(.title3)
                .foregroundStyle(.secondary)

            if let project = session.activeProject {
                let guidance = project.stage.journeyGuidance

                GroupBox("Aktives Projekt") {
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Als Nächstes")
                                .font(.caption.weight(.semibold))
                            Text(guidance.nextAction)
                                .font(.callout)
                        }

                        if guidance.recommendedSurface == .studio {
                            Button {
                                onOpenStudio()
                            } label: {
                                Label(
                                    "Im Editor fortfahren",
                                    systemImage: "arrow.right.circle.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
            }

            if let project = session.activeProject,
               project.stage == .research
                || project.stage == .analysis {
                ResearchAnalysisJourneyView(
                    session: session,
                    project: project
                )
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

private struct ResearchAnalysisJourneyView: View {
    @ObservedObject var session: BlackstockSession
    let project: BlackstockProject

    @State private var researchQuestion = ""
    @State private var creatorNotes = ""
    @State private var decision: ProductionDecision = .pursue
    @State private var rationale = ""
    @State private var riskOrUnknown = ""

    var body: some View {
        GroupBox(
            project.stage == .research
                ? "Recherchebelege"
                : "Analyse & Produktionsentscheidung"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if session.productionIntent(
                    for: project.id
                )?.isLinkFirstClip == true {
                    Label(
                        "Clip-Vorhaben aus Opportunity",
                        systemImage: "scissors"
                    )
                    .font(.headline)
                    Text("Der ausgewählte Quelllink bleibt an dieses Projekt gebunden. Research und Analyse werden trotzdem vollständig abgeschlossen, bevor Blackstock ein Produktionsmedium übernimmt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                }

                if project.stage == .research {
                    researchContent
                } else {
                    analysisContent
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
        .task(id: project.updatedAt) {
            loadPersistedEvidence()
        }
    }

    @ViewBuilder
    private var researchContent: some View {
        if let record = session.loadResearchEvidence(
            projectID: project.id
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Eingefrorene Provider-Fakten")
                    .font(.headline)
                ForEach(
                    Array(record.providerFacts.enumerated()),
                    id: \.offset
                ) { _, fact in
                    Label(fact, systemImage: "checkmark.circle")
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Text(
                    "Quelle: \(record.source.pageURL.absoluteString)"
                )
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            Divider()

            TextField(
                "Recherchefrage",
                text: $researchQuestion
            )
            .textFieldStyle(.roundedBorder)

            Text("Eigene Notizen und Einordnung")
                .font(.caption.weight(.semibold))
            TextEditor(text: $creatorNotes)
                .frame(minHeight: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            Text("Provider-Fakten werden nicht überschrieben. Deine eigene Einordnung wird separat gespeichert.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                _ = session.completeResearch(
                    question: researchQuestion,
                    creatorNotes: creatorNotes
                )
            } label: {
                Label(
                    "Recherche abschließen und analysieren",
                    systemImage: "arrow.right.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
        } else {
            Label(
                "Gebundene Recherchebelege fehlen. Das Projekt kann nicht fortgesetzt werden.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var analysisContent: some View {
        if let research = session.loadResearchEvidence(
            projectID: project.id
        ), research.isComplete {
            VStack(alignment: .leading, spacing: 5) {
                Text("Belegte Recherche")
                    .font(.headline)
                Text(research.researchQuestion)
                    .font(.callout.weight(.semibold))
                Text(research.creatorNotes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker(
                "Produktionsentscheidung",
                selection: $decision
            ) {
                Text("Weiterverfolgen").tag(ProductionDecision.pursue)
                Text("Verwerfen").tag(ProductionDecision.reject)
            }
            .pickerStyle(.segmented)

            TextField(
                "Begründung der Entscheidung",
                text: $rationale
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Offenes Risiko oder unbekannter Punkt",
                text: $riskOrUnknown
            )
            .textFieldStyle(.roundedBorder)

            Text("Blackstock verlangt ausdrücklich mindestens eine verbleibende Unsicherheit statt eine Sicherheit vorzutäuschen.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                _ = session.completeAnalysis(
                    decision: decision,
                    rationale: rationale,
                    riskOrUnknown: riskOrUnknown
                )
            } label: {
                Label(
                    decision == .pursue
                        ? "Entscheidung speichern und Produktion freigeben"
                        : "Verwerfen und Entscheidung speichern",
                    systemImage: decision == .pursue
                        ? "checkmark.circle.fill"
                        : "xmark.circle"
                )
            }
            .buttonStyle(.borderedProminent)
        } else {
            Label(
                "Vollständige Recherchebelege fehlen. Analyse ist gesperrt.",
                systemImage: "lock.fill"
            )
        }
    }

    private func loadPersistedEvidence() {
        if let research = session.loadResearchEvidence(
            projectID: project.id
        ) {
            researchQuestion = research.researchQuestion
            creatorNotes = research.creatorNotes
        }
        if let analysis = session.loadAnalysisDecision(
            projectID: project.id
        ) {
            decision = analysis.decision
            rationale = analysis.rationale
            riskOrUnknown = analysis.riskOrUnknown
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var session: BlackstockSession
    @State private var showOAuthImporter = false
    @State private var showOAuthConfigurationRemovalConfirmation = false
    @State private var oauthConfigurationStatusMessage: String?
    @State private var showCredentialRemovalConfirmation = false
    @State private var credentialStatusMessage: String?
    @State private var isRevokingGoogleAccess = false
    @State private var privacyExportStatusMessage: String?
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
                    HStack(spacing: 10) {
                        Button {
                            showOAuthImporter = true
                        } label: {
                            Label(
                                session.hasImportedOAuthConfiguration
                                    ? "Desktop-OAuth-JSON ersetzen …"
                                    : "Desktop-OAuth-JSON importieren …",
                                systemImage: "doc.badge.plus"
                            )
                        }

                        Button(
                            "Importierte OAuth-Konfiguration entfernen",
                            role: .destructive
                        ) {
                            showOAuthConfigurationRemovalConfirmation = true
                        }
                        .disabled(
                            !session.hasImportedOAuthConfiguration
                        )
                    }

                    Text("Die Desktop-OAuth-Konfiguration wird lokal im macOS-Schlüsselbund gespeichert. Bei einem Client-Wechsel wird Google neu autorisiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let oauthConfigurationStatusMessage {
                        Text(oauthConfigurationStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Button(
                        "Lokale YouTube-Anmeldung entfernen",
                        role: .destructive
                    ) {
                        showCredentialRemovalConfirmation = true
                    }

                    Text("Entfernt die lokale YouTube-Anmeldung. Projekte bleiben erhalten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            isRevokingGoogleAccess = true
                            defer { isRevokingGoogleAccess = false }
                            do {
                                let removed = try await session
                                    .revokeGoogleAuthorization()
                                credentialStatusMessage = removed > 0
                                    ? "Google-Berechtigung wurde widerrufen und \(removed) lokale Keychain-Einträge wurden entfernt."
                                    : "Google-Berechtigung wurde widerrufen; es waren keine lokalen YouTube-Keychain-Einträge gespeichert."
                            } catch {
                                credentialStatusMessage = "Google-Berechtigung konnte nicht vollständig widerrufen werden: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            if isRevokingGoogleAccess {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                isRevokingGoogleAccess
                                    ? "Google-Berechtigung wird widerrufen …"
                                    : "Google-Berechtigung widerrufen",
                                systemImage: "person.crop.circle.badge.xmark"
                            )
                        }
                    }
                    .disabled(isRevokingGoogleAccess)

                    Text("Widerruft den Google-Zugriff und entfernt die lokale Anmeldung.")
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

                        if let manifest = availableUpdateManifest {
                            Button {
                                do {
                                    try BlackstockUpdateInstallationPreflight()
                                        .verify(
                                            fileURL:
                                                verifiedUpdatePackageURL,
                                            manifest: manifest
                                        )
                                    BlackstockUpdateAudit
                                        .recordVerifiedPackage(
                                            manifest: manifest
                                        )
                                    guard NSWorkspace.shared.open(
                                        verifiedUpdatePackageURL
                                    ) else {
                                        updateStatusMessage = "Das erneut verifizierte Paket konnte nicht im macOS-Installer geöffnet werden."
                                        return
                                    }
                                    BlackstockUpdateAudit.recordInstallerOpened(
                                        manifest: manifest
                                    )
                                    updateStatusMessage = "SHA-256 und Developer-ID-Installer-Team wurden unmittelbar vor der Übergabe erneut verifiziert. Das Paket wurde an den macOS-Installer übergeben; die Installation erfolgt erst nach deiner Bestätigung im System-Installer."
                                } catch {
                                    try? FileManager.default.removeItem(
                                        at: verifiedUpdatePackageURL
                                    )
                                    self.verifiedUpdatePackageURL = nil
                                    updateStatusMessage = "Das Paket hat den erneuten Installations-Preflight für SHA-256 und Developer-ID-Installer-Team nicht bestanden, wurde gelöscht und nicht geöffnet."
                                }
                            } label: {
                                Label(
                                    "Verifiziertes Paket im macOS-Installer öffnen",
                                    systemImage: "shippingbox"
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            GroupBox("Capture-Hardware-Evidenz") {
                VStack(alignment: .leading, spacing: 10) {
                    if let evidence =
                        BlackstockCaptureHardwareAudit.loadEvidence() {
                        HStack {
                            Label(
                                evidence.isComplete
                                    ? "Hardware-Nachweis vollständig"
                                    : "Hardware-Nachweis noch unvollständig",
                                systemImage: evidence.isComplete
                                    ? "checkmark.seal.fill"
                                    : "externaldrive.badge.exclamationmark"
                            )
                            .font(.callout.weight(.semibold))
                            Spacer()
                            Text(
                                "\(CaptureKind.allCases.filter { evidence[$0].satisfies(kind: $0) }.count)/4 Pfade"
                            )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }

                        ForEach(CaptureKind.allCases, id: \.self) { kind in
                            let path = evidence[kind]
                            HStack {
                                Image(
                                    systemName:
                                        path.satisfies(kind: kind)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.germanTitle)
                                        .font(.caption.weight(.semibold))
                                    Text(
                                        captureEvidenceDetail(
                                            path,
                                            kind: kind
                                        )
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }

                        Divider()

                        Label(
                            evidence.deniedPermissionHardStopPassed
                                ? "Verweigerte Berechtigungen: Hard-Stop belegt"
                                : "Verweigerte Berechtigungen noch nicht vollständig getestet",
                            systemImage:
                                evidence.deniedPermissionHardStopPassed
                                ? "hand.raised.fill"
                                : "hand.raised"
                        )
                        .font(.caption)

                        Label(
                            evidence.temporaryCleanupPassed
                                ? "Temporäre Capture-Dateien: Cleanup belegt"
                                : "Temporärer Cleanup noch nicht für alle Pfade belegt",
                            systemImage:
                                evidence.temporaryCleanupPassed
                                ? "trash.slash.fill"
                                : "trash"
                        )
                        .font(.caption)

                        Label(
                            evidence.appRestartPersistencePassed
                                ? "Projektpersistenz nach App-Neustart belegt"
                                : "App-Neustart-Persistenz noch nicht belegt",
                            systemImage:
                                evidence.appRestartPersistencePassed
                                ? "arrow.clockwise.circle.fill"
                                : "arrow.clockwise.circle"
                        )
                        .font(.caption)

                        if let url =
                            BlackstockCaptureHardwareAudit.evidenceURL() {
                            Text(url.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Button {
                                NSWorkspace.shared
                                    .activateFileViewerSelecting(
                                        [url]
                                    )
                            } label: {
                                Label(
                                    "Evidenzdatei im Finder zeigen",
                                    systemImage: "folder"
                                )
                            }
                        }

                        Text(
                            evidence.isComplete
                                ? "Die App-Evidenz erfüllt intern alle Capture-Hardware-Bedingungen. Das Release-Gate wird erst nach externer Validierung dieser Datei auf PASS gesetzt."
                                : "Für Capture = PASS müssen alle vier realen Pfade mindestens fünf Sekunden technisch valide aufgezeichnet, projektgebunden, bereinigt und nach einem App-Neustart nachweisbar sein."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Noch keine Capture-Hardware-Evidenz vorhanden. Sie entsteht automatisch durch reale Aufnahmen und Berechtigungs-Hard-Stops in einem installierten Blackstock-Build.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            GroupBox("Datenschutz & lokale Daten") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blackstock speichert Projekt-, Wachstums- und Arbeitsbereichsdaten lokal im Benutzerprofil. Google-/YouTube-Zugangsdaten liegen im macOS-Keychain.")

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Exportieren"
                        panel.message = "Wähle einen lokalen Ordner für deinen Blackstock-Datenschutzexport."
                        if panel.runModal() == .OK,
                           let destination = panel.url {
                            do {
                                let report = try session.exportLocalPrivacyData(
                                    to: destination
                                )
                                privacyExportStatusMessage = "Datenschutzexport erstellt: \(report.exportURL.path). Keychain-Tokens sind nicht enthalten."
                            } catch {
                                privacyExportStatusMessage = "Datenschutzexport fehlgeschlagen: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        Label(
                            "Lokale Blackstock-Daten exportieren",
                            systemImage: "square.and.arrow.up"
                        )
                    }

                    Text("Der Export bleibt lokal im gewählten Ordner und enthält keine OAuth-Access-/Refresh-Tokens oder andere Keychain-Geheimnisse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let privacyExportStatusMessage {
                        Text(privacyExportStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Divider()

                    Text("Aufbewahrung")
                        .font(.headline)
                    ForEach(
                        Array(PrivacyRetentionPolicy.canonical.enumerated()),
                        id: \.offset
                    ) { _, rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.dataClass)
                                .font(.caption.weight(.semibold))
                            Text(rule.rationale)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Button(
                        "Alle lokalen Blackstock-Daten löschen",
                        role: .destructive
                    ) {
                        showLocalDataRemovalConfirmation = true
                    }

                    Text("Löscht lokale Projekte, Renderings, Untertitel, Vorschaubilder, Wachstumsdaten, Blackstock-Einstellungen, gespeicherte Google-/YouTube-Anmeldedaten und eine importierte OAuth-Client-Konfiguration von diesem Mac.")
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
        .fileImporter(
            isPresented: $showOAuthImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    oauthConfigurationStatusMessage =
                        "Es wurde keine OAuth-JSON ausgewählt."
                    return
                }
                if session.importOAuthJSON(from: url) {
                    oauthConfigurationStatusMessage =
                        "Desktop-OAuth-Konfiguration wurde sicher übernommen."
                } else {
                    oauthConfigurationStatusMessage =
                        session.errorMessage
                        ?? "OAuth-Konfiguration konnte nicht übernommen werden."
                }
            case .failure(let error):
                oauthConfigurationStatusMessage =
                    "OAuth-JSON konnte nicht ausgewählt werden: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Importierte OAuth-Konfiguration entfernen?",
            isPresented:
                $showOAuthConfigurationRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "OAuth-Konfiguration entfernen",
                role: .destructive
            ) {
                if session.removeImportedOAuthConfiguration() {
                    oauthConfigurationStatusMessage =
                        "Importierte OAuth-Konfiguration wurde entfernt."
                } else {
                    oauthConfigurationStatusMessage =
                        session.errorMessage
                        ?? "OAuth-Konfiguration konnte nicht entfernt werden."
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Wenn dadurch die effektive Google-Client-ID wechselt, entfernt Blackstock die daran gebundenen lokalen YouTube-Tokens und verlangt eine neue Autorisierung.")
        }
    }

    private func captureEvidenceDetail(
        _ evidence: CaptureHardwarePathEvidence,
        kind: CaptureKind
    ) -> String {
        guard evidence.recordingCreated else {
            return "Noch keine technisch vermessene Aufnahme."
        }

        var parts = [
            String(
                format: "%.1f s",
                evidence.durationSeconds
            )
        ]
        if kind == .camera || kind == .screen {
            parts.append(
                evidence.videoTrackPresent == true
                    ? "Videospur erkannt"
                    : "Videospur fehlt"
            )
        }
        if kind == .microphone || kind == .systemAudio {
            parts.append(
                "\(evidence.decodedSamples ?? 0) dekodierte Samples"
            )
        }
        parts.append(
            evidence.persistedToProject
                ? "im Projekt gespeichert"
                : "nicht projektgebunden"
        )
        return parts.joined(separator: " · ")
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
