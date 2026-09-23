#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

@main
struct BlackstockApp: App {
    @StateObject private var session = BlackstockSession()
    @State private var commandPaletteRequest = 0
    @State private var keychainMessage: String?
    @State private var retryingKeychain = false

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
            .safeAreaInset(edge: .top) {
                if let keychainMessage {
                    HStack {
                        Label(keychainMessage, systemImage: "lock.trianglebadge.exclamationmark")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Neu anmelden") { session.showGoogleConnection = true }
                        Button("Zugriff erneut prüfen") {
                            retryingKeychain = true
                            Task {
                                await session.retryKeychainAccess()
                                retryingKeychain = false
                            }
                        }
                        .disabled(retryingKeychain)
                    }
                    .padding()
                    .background(.regularMaterial)
                } else if session.onboardingComplete && session.workspaceChannel == nil {
                    HStack {
                        Text("Verbinde Google und wähle deinen YouTube-Kanal.")
                        Spacer()
                        Button("Mit Google / YouTube anmelden") {
                            session.showGoogleConnection = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .onReceive(BlackstockKeychain.accessIssue) { keychainMessage = $0 }
            .sheet(isPresented: $session.showGoogleConnection) {
                GoogleAccountConnectionView(session: session)
            }
            .frame(minWidth: 1180, minHeight: 760)
            .tint(BlackstockDesign.accent)
            .background(BlackstockDesign.canvas)
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
                HStack(alignment: .center, spacing: 10) {
                    BlackstockBrandMark(width: 34)

                    Text("Blackstock")
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 14)
                .background(BlackstockDesign.sidebar)

                Divider()

                List(selection: $selection) {
                    Label("Start", systemImage: "house")
                        .tag("Übersicht")
                    Label("Entdecken", systemImage: "play.rectangle.fill")
                        .tag("Chancen")
                    Label("Projekte", systemImage: "folder.fill")
                        .tag("Projekte")
                    Label("Analyse", systemImage: "chart.line.uptrend.xyaxis")
                        .tag("Analyse")
                    if session.activeProject?.stage.journeyGuidance
                        .recommendedSurface == .studio {
                        Label("Editor", systemImage: "scissors")
                            .tag("Studio")
                    }
                    Label("Einstellungen", systemImage: "gearshape")
                        .tag("Einstellungen")
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(BlackstockDesign.sidebar)
            }
            .background(BlackstockDesign.sidebar)
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
                        selection =
                            session.activeProject?.stage.journeyGuidance
                                .recommendedSurface == .studio
                            ? "Studio"
                            : "Übersicht"
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
            case "Analyse":
                ChannelAnalyticsWorkspaceView(
                    session: session
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
                        onOpenStudio: { selection = "Studio" },
                        onNavigate: { selection = $0 }
                    )
                }
            case "Einstellungen":
                SettingsView(session: session)
            default:
                OverviewView(
                    session: session,
                    onOpenStudio: { selection = "Studio" },
                    onNavigate: { selection = $0 }
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(BlackstockDesign.canvas)
        .task {
            routeToCurrentProject()
        }
        .onChange(of: session.activeProject?.stage) { _ in
            routeToCurrentProject()
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

    private func routeToCurrentProject() {
        guard let project = session.activeProject else {
            if selection == "Studio" {
                selection = "Übersicht"
            }
            return
        }

        switch project.stage.journeyGuidance.recommendedSurface {
        case .studio:
            selection = "Studio"
        case .overview:
            selection = "Übersicht"
        case .none:
            if project.stage == .discovery {
                selection = "Chancen"
            }
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
                title: "Start öffnen",
                subtitle: "Zur Startseite",
                systemImage: "rectangle.grid.2x2",
                destination: "Übersicht",
                isDestructive: false
            ),
            .init(
                id: "opportunities",
                title: "Videos öffnen",
                subtitle: "YouTube-Videos suchen",
                systemImage: "sparkle.magnifyingglass",
                destination: "Chancen",
                isDestructive: false
            ),
            .init(
                id: "projects",
                title: "Projekte öffnen",
                subtitle: "Gespeicherte Projekte",
                systemImage: "tray.full",
                destination: "Projekte",
                isDestructive: false
            )
,
            .init(
                id: "analytics",
                title: "Analyse öffnen",
                subtitle: "Kanal-KPIs und YouTube Analytics",
                systemImage: "chart.line.uptrend.xyaxis",
                destination: "Analyse",
                isDestructive: false
            )
        ]

        if hasActiveProject {
            result.append(
                .init(
                    id: "studio",
                    title: "Editor öffnen",
                    subtitle: "Aktuelles Projekt bearbeiten",
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
                subtitle: "Konto und App",
                systemImage: "gearshape",
                destination: "Einstellungen",
                isDestructive: false
            ),
            .init(
                id: "restart-first-run",
                title: "Einrichtung zurücksetzen",
                subtitle: "Google und Kanal neu einrichten",
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
    let onNavigate: (String) -> Void

    private struct WorkflowStep: Identifiable {
        let id: Int
        let title: String
        let systemImage: String
    }

    private var workflowSteps: [WorkflowStep] {
        [
            .init(
                id: 0,
                title: "Entdecken",
                systemImage: "play.rectangle.fill"
            ),
            .init(
                id: 1,
                title: "Projekt",
                systemImage: "folder.fill"
            ),
            .init(
                id: 2,
                title: "Editor",
                systemImage: "scissors"
            ),
            .init(
                id: 3,
                title: "Review",
                systemImage: "checkmark.seal.fill"
            ),
            .init(
                id: 4,
                title: "Upload",
                systemImage: "arrow.up.circle.fill"
            ),
            .init(
                id: 5,
                title: "Analyse",
                systemImage: "chart.line.uptrend.xyaxis"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader
                dashboardMetrics
                workflowCard
                activeProjectCard

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
            }
            .frame(
                maxWidth: 1180,
                alignment: .leading
            )
            .padding(28)
        }
        .background(BlackstockDesign.canvas)
        .task {
            await session.refreshWorkspaceChannelIdentity()
            if session.analyticsAuthorizedChannelID
                    == session.workspaceChannelID,
               session.latestChannelAnalytics == nil {
                await session.collectChannelAnalytics(
                    days: 28
                )
            }
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Creator Dashboard")
                    .font(.largeTitle.bold())
                Text(
                    session.workspaceChannel?.title
                    ?? "Dein Blackstock-Workflow"
                )
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onNavigate("Chancen")
            } label: {
                Label(
                    "Entdecken",
                    systemImage: "sparkle.magnifyingglass"
                )
            }
            .buttonStyle(.bordered)

            Button {
                onNavigate("Analyse")
            } label: {
                Label(
                    "Kanal analysieren",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var dashboardMetrics: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: 190,
                        maximum: 280
                    ),
                    spacing: 12
                )
            ],
            spacing: 12
        ) {
            dashboardMetric(
                title: "Abonnenten",
                value: compactDashboardNumber(
                    session.workspaceChannel?.subscriberCount
                ),
                systemImage: "person.2.fill"
            )
            dashboardMetric(
                title: "Views · 28 Tage",
                value: compactDashboardNumber(
                    session.latestChannelAnalytics?.views
                ),
                systemImage: "play.rectangle.fill"
            )
            dashboardMetric(
                title: "Projekte",
                value: String(session.projects.count),
                systemImage: "folder.fill"
            )
            dashboardMetric(
                title: "Aktueller Schritt",
                value:
                    session.activeProject?
                        .stage.journeyGuidance.title
                    ?? "Bereit",
                systemImage: "bolt.fill"
            )
        }
    }

    private var workflowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workflow")
                        .font(.title2.bold())
                    Text(
                        "Von der YouTube-Idee bis Upload und Lernschleife"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let project = session.activeProject {
                    Text(
                        "Schritt "
                        + String(
                            currentWorkflowIndex(
                                for: project.stage
                            ) + 1
                        )
                        + " / "
                        + String(workflowSteps.count)
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(workflowSteps) { step in
                    let activeIndex =
                        session.activeProject.map {
                            currentWorkflowIndex(
                                for: $0.stage
                            )
                        } ?? 0
                    let isCurrent =
                        step.id == activeIndex
                    let isComplete =
                        step.id < activeIndex

                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    isCurrent || isComplete
                                    ? BlackstockDesign
                                        .selectedFill
                                    : Color.primary
                                        .opacity(0.035)
                                )
                                .frame(
                                    width: 38,
                                    height: 38
                                )
                            Image(
                                systemName:
                                    isComplete
                                    ? "checkmark"
                                    : step.systemImage
                            )
                            .font(
                                .caption.weight(.bold)
                            )
                            .foregroundStyle(
                                isCurrent
                                ? BlackstockDesign.accent
                                : .secondary
                            )
                        }

                        Text(step.title)
                            .font(
                                .caption.weight(
                                    isCurrent
                                    ? .semibold
                                    : .regular
                                )
                            )
                            .foregroundStyle(
                                isCurrent
                                ? .primary
                                : .secondary
                            )
                    }
                    .frame(
                        maxWidth: .infinity
                    )

                    if step.id
                        < workflowSteps.count - 1 {
                        Rectangle()
                            .fill(
                                step.id < activeIndex
                                ? BlackstockDesign
                                    .selectedBorder
                                : Color.primary
                                    .opacity(0.08)
                            )
                            .frame(
                                height: 2
                            )
                            .frame(maxWidth: 36)
                    }
                }
            }
        }
        .padding(20)
        .blackstockSurface(raised: true)
    }

    @ViewBuilder
    private var activeProjectCard: some View {
        if let project = session.activeProject {
            let guidance = project.stage.journeyGuidance

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Aktuelles Projekt")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(project.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Text(guidance.purpose)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(guidance.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            BlackstockDesign.selectedFill,
                            in: Capsule()
                        )
                }

                ProgressView(
                    value: Double(
                        project.stage
                            .canonicalProgressPosition
                    ),
                    total: Double(
                        BlackstockStage
                            .canonicalProgressCount
                    )
                )
                .accessibilityLabel("Projektfortschritt")

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Als Nächstes")
                            .font(.caption.weight(.semibold))
                        Text(guidance.nextAction)
                            .font(.callout)
                    }

                    Spacer()

                    if guidance.recommendedSurface == .studio {
                        Button {
                            onOpenStudio()
                        } label: {
                            Label(
                                project.stage == .review
                                    || project.stage == .publishing
                                    ? "Upload fortsetzen"
                                    : "Im Editor fortfahren",
                                systemImage: "arrow.right.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    } else if project.stage == .published {
                        Button {
                            onNavigate("Analyse")
                        } label: {
                            Label(
                                "Ergebnisse ansehen",
                                systemImage: "chart.bar.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            onNavigate("Projekte")
                        } label: {
                            Label(
                                "Projekt öffnen",
                                systemImage: "folder"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .blackstockSurface(raised: true)
        } else {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .fill(
                        BlackstockDesign.selectedFill
                    )
                    Image(
                        systemName:
                            "play.rectangle.fill"
                    )
                    .font(.title)
                    .foregroundStyle(
                        BlackstockDesign.accent
                    )
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Neues Video starten")
                        .font(.headline)
                    Text(
                        "Entdecke ein Video, erstelle Clips und veröffentliche das Ergebnis direkt auf deinem YouTube-Kanal."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onNavigate("Chancen")
                } label: {
                    Label(
                        "Video entdecken",
                        systemImage: "arrow.right"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .blackstockSurface(raised: true)
        }
    }

    private func dashboardMetric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(
                    .title2.bold()
                        .monospacedDigit()
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 92,
            alignment: .leading
        )
        .padding(16)
        .blackstockSurface(raised: true)
    }

    private func compactDashboardNumber(
        _ value: Int?
    ) -> String {
        guard let value else { return "—" }
        if abs(value) >= 1_000_000 {
            return String(
                format: "%.1fM",
                Double(value) / 1_000_000
            )
        }
        if abs(value) >= 1_000 {
            return String(
                format: "%.1fK",
                Double(value) / 1_000
            )
        }
        return String(value)
    }

    private func currentWorkflowIndex(
        for stage: BlackstockStage
    ) -> Int {
        switch stage {
        case .discovery:
            return 0
        case .research, .analysis:
            return 1
        case .production,
             .preview,
             .storyboard,
             .editing,
             .packaging:
            return 2
        case .review:
            return 3
        case .publishing:
            return 4
        case .published:
            return 5
        }
    }

    @ViewBuilder
    private func growthLoopCard(
        project: BlackstockProject,
        record: PublishedVideoRecord
    ) -> some View {
        GroupBox("Kanal- & Videoanalyse") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    YouTubeEmbeddedPlayer(
                        videoID: record.youtubeVideoID
                    )
                    .aspectRatio(
                        16.0 / 9.0,
                        contentMode: .fit
                    )
                    .background(BlackstockDesign.mediaSurface)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: BlackstockDesign.cornerRadius,
                            style: .continuous
                        )
                    )

                    Text(project.title)
                        .font(.headline)

                    if let category =
                        session.projectChannelCategoryTitle(
                            for: project.id
                        ) {
                        Label(
                            "Kanal-Kategorie: \(category)",
                            systemImage: "tag"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
                                await session
                                    .collectDueGrowthObservations()
                                await session
                                    .collectChannelAnalytics()
                            }
                        } label: {
                            HStack {
                                if session.isCollectingAnalytics {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    session.isCollectingAnalytics
                                        ? "Daten werden aktualisiert …"
                                        : "Kanal & Video aktualisieren",
                                    systemImage: "chart.line.uptrend.xyaxis"
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            session.isCollectingAnalytics
                        )

                        if due.isEmpty {
                            Text("Die aktuellen Daten sind bereits geladen.")
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
                                    ? "YouTube wird verbunden …"
                                    : "Videoanalyse verbinden",
                                systemImage: "key"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.isAuthorizingAnalytics)
                }

                if !due.isEmpty {
                    Text(
                        "Bereit für Aktualisierung: "
                        + due.map { $0.window.germanTitle }
                            .joined(separator: ", ")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let next {
                    Text(
                        "Nächste Aktualisierung: "
                        + next.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let channel =
                    session.latestChannelAnalytics {
                    Divider()
                    VStack(
                        alignment: .leading,
                        spacing: 7
                    ) {
                        Text("Kanalanalyse · 28 Tage")
                            .font(.headline)
                        HStack(spacing: 16) {
                            if let views = channel.views {
                                Label(
                                    "\(views) Views",
                                    systemImage: "play.rectangle"
                                )
                            }
                            if let minutes =
                                channel.estimatedMinutesWatched {
                                Label(
                                    String(
                                        format:
                                            "%.0f Min. Wiedergabezeit",
                                        minutes
                                    ),
                                    systemImage: "clock"
                                )
                            }
                            if let net =
                                channel.netSubscribers {
                                Label(
                                    "\(net >= 0 ? "+" : "")\(net) Abonnenten",
                                    systemImage: "person.badge.plus"
                                )
                            }
                        }
                        .font(.caption)

                        Text(
                            channel.startDate
                            + " – "
                            + channel.endDate
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                if let learning = session.latestGrowthLearning {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ergebnisse")
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
                    Text("Noch keine YouTube-Analyse verfügbar. Daten können nach der Veröffentlichung zeitversetzt erscheinen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YouTube-Kommentare")
                                .font(.headline)
                            Text("Kommentare zum veröffentlichten Video")
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
                                        : "Kommentare laden",
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
                ? "Recherche"
                : "Analyse & Produktionsentscheidung"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if session.productionIntent(
                    for: project.id
                )?.isLinkFirstClip == true {
                    Label(
                        "Clip-Projekt",
                        systemImage: "scissors"
                    )
                    .font(.headline)
                    Text("Das ausgewählte Video bleibt mit diesem Projekt verknüpft.")
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
                Text("Videodaten")
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

            Text("Die Angaben zum Video bleiben unverändert; deine Notizen werden separat gespeichert.")
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
                "Gebundene Recherche fehlen. Das Projekt kann nicht fortgesetzt werden.",
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
                Text("Recherche")
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
                "Vollständige Recherche fehlen. Analyse ist gesperrt.",
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
                    Button("Mit Google / YouTube anmelden") {
                        session.connectionStatusMessage = nil
                        session.errorMessage = nil
                        session.showGoogleConnection = true
                    }
                    .buttonStyle(.borderedProminent)
                    if let channel = session.workspaceChannel {
                        Text("Verbunden mit " + channel.title)
                    }
                    Text("Wähle deinen Kanal nach der Google-Anmeldung. Ein Kanal ist nicht vorgegeben.")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Erweiterte App-Einstellungen") {
                    Text(session.oauthConfigurationSource)
                        .font(.caption)
                        .foregroundStyle(.secondary)

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

                    Text("Eine importierte Desktop-OAuth-Datei bleibt lokal. Client-ID, optionales Client-Secret und YouTube-Zugangsdaten werden sicher im macOS-Keychain verwendet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let oauthConfigurationStatusMessage {
                        Text(oauthConfigurationStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    }

                    Divider()

                    Button(
                        "Lokale YouTube-Anmeldung entfernen",
                        role: .destructive
                    ) {
                        showCredentialRemovalConfirmation = true
                    }

                    Text("Meldet Blackstock auf diesem Mac von YouTube ab. Projekte bleiben erhalten.")
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

                    Text("Entfernt die Google-Berechtigung und meldet Blackstock ab.")
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

            GroupBox("Original-Mediathek") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        session.originalMediaLibraryPath.isEmpty
                            ? "Noch kein Ordner ausgewählt."
                            : session.originalMediaLibraryPath
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)

                    HStack(spacing: 10) {
                        Button {
                            chooseOriginalMediaLibrary()
                        } label: {
                            Label(
                                session.originalMediaLibraryPath.isEmpty
                                    ? "Originalvideo-Ordner wählen …"
                                    : "Originalvideo-Ordner ändern …",
                                systemImage: "folder.badge.plus"
                            )
                        }

                        Button(
                            "Ordnerzuordnung entfernen",
                            role: .destructive
                        ) {
                            _ = session.setOriginalMediaLibrary(nil)
                        }
                        .disabled(
                            session.originalMediaLibraryPath.isEmpty
                        )
                    }

                    Text(
                        "Blackstock durchsucht diesen Ordner lokal nach dem passenden Original, wenn du ein YouTube-Video als Clip auswählst. Ein eindeutiger Treffer wird automatisch ans Projekt gebunden; sonst bleibt die manuelle Dateiauswahl als Fallback."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
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

                    Text("Updates werden vor der Installation geprüft.")
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
                                    updateStatusMessage = "Das Update wurde erneut verifiziert und an den macOS-Installer übergeben. Blackstock wird jetzt beendet, damit die neue Version sauber installiert werden kann."
                                    DispatchQueue.main.asyncAfter(
                                        deadline: .now() + 0.4
                                    ) {
                                        NSApp.terminate(nil)
                                    }
                                } catch {
                                    try? FileManager.default.removeItem(
                                        at: verifiedUpdatePackageURL
                                    )
                                    self.verifiedUpdatePackageURL = nil
                                    updateStatusMessage = "Das Paket hat den erneuten Installations-Preflight für SHA-256 und Developer-ID-Installer-Team nicht bestanden, wurde gelöscht und nicht geöffnet."
                                }
                            } label: {
                                Label(
                                    "Update installieren und Blackstock schließen",
                                    systemImage: "shippingbox"
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            DisclosureGroup("Diagnose") {
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
                                ? "Berechtigungen korrekt behandelt"
                                : "Verweigerte Berechtigungen noch nicht vollständig getestet",
                            systemImage:
                                evidence.deniedPermissionHardStopPassed
                                ? "hand.raised.fill"
                                : "hand.raised"
                        )
                        .font(.caption)

                        Label(
                            evidence.temporaryCleanupPassed
                                ? "Temporäre Aufnahmedateien bereinigt"
                                : "Bereinigung noch nicht vollständig geprüft",
                            systemImage:
                                evidence.temporaryCleanupPassed
                                ? "trash.slash.fill"
                                : "trash"
                        )
                        .font(.caption)

                        Label(
                            evidence.appRestartPersistencePassed
                                ? "Projekt bleibt nach Neustart erhalten"
                                : "Neustart-Verhalten noch nicht vollständig geprüft",
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
                                    "Diagnosedatei im Finder zeigen",
                                    systemImage: "folder"
                                )
                            }
                        }

                        Text(
                            evidence.isComplete
                                ? "Kamera, Mikrofon, Bildschirm und Systemaudio wurden erfolgreich geprüft."
                                : "Einige Aufnahmewege wurden auf diesem Mac noch nicht vollständig geprüft."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Noch keine vollständige Aufnahmediagnose vorhanden.")
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

    private func chooseOriginalMediaLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Originalvideo-Ordner auswählen"
        panel.prompt = "Ordner verwenden"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }
        _ = session.setOriginalMediaLibrary(url)
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
