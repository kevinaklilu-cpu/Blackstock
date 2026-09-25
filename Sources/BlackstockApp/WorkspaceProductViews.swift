#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import BlackstockCore

struct OpportunityWorkspaceView: View {
    @ObservedObject var session: BlackstockSession
    let onProjectCreated: () -> Void

    @AppStorage("blackstock.discovery.query")
    private var query = ""
    @State private var sortMode: OpportunitySortMode = .views
    @State private var selectedOpportunityID: String?
    @State private var hasLoadedInitially = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        "YouTube durchsuchen",
                        text: $query
                    )
                    .textFieldStyle(.plain)
                    .accessibilityLabel("YouTube-Suchbegriff")
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Suchbegriff löschen")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .blackstockSurface(raised: true)
                .onSubmit {
                    Task { await loadOpportunities() }
                }

                HStack(spacing: 10) {
                Picker(
                    "Format",
                    selection: $session.opportunityContentFilter
                ) {
                    ForEach(
                        OpportunityContentFilter.allCases,
                        id: \.self
                    ) { filter in
                        Text(filter.germanTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Picker(
                    "Zeitraum",
                    selection: $session.opportunityTimeWindow
                ) {
                    ForEach(
                        OpportunityTimeWindow.allCases,
                        id: \.self
                    ) { window in
                        Text(window.germanTitle).tag(window)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("Sortierung", selection: $sortMode) {
                    ForEach(OpportunitySortMode.allCases, id: \.self) { mode in
                        Text(mode.germanTitle).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 175)

                Button {
                    Task { await loadOpportunities() }
                } label: {
                    HStack {
                        if session.isLoadingOpportunities {
                            ProgressView().controlSize(.small)
                        }
                        Label(
                            session.isLoadingOpportunities
                                ? "Lädt …"
                                : "Suchen",
                            systemImage: "magnifyingglass"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BlackstockDesign.accent)
                .disabled(session.isLoadingOpportunities)
            }

            }

            HStack(spacing: 10) {
                Picker(
                    "Kategorie",
                    selection: $session.channelCategoryID
                ) {
                    Text("Alle Kategorien").tag("")
                    ForEach(
                        session.youtubeVideoCategories
                            .filter(\.assignable)
                    ) { category in
                        Text(category.title)
                            .tag(category.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 190, idealWidth: 240)

                Picker(
                    "Region",
                    selection: $session.channelRegionCode
                ) {
                    ForEach(session.youtubeRegions) { region in
                        Text(region.name)
                            .tag(region.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)

                Picker(
                    "Sprache",
                    selection: $session.contentLanguage
                ) {
                    ForEach(session.youtubeLanguages) { language in
                        Text(language.name)
                            .tag(language.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)

                Spacer()

                if session.isLoadingYouTubeSetupOptions {
                    ProgressView()
                        .controlSize(.small)
                    Text("YouTube-Parameter werden geladen …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        "YouTube Data API",
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("\(session.opportunities.count) Videos · \(sortMode.germanTitle)")
                    .font(.callout.weight(.semibold))
                Spacer()
                if session.isLoadingOpportunities {
                    ProgressView().controlSize(.small)
                    Text("Videos und Aufrufzahlen werden geladen …").font(.caption)
                } else if session.opportunityNextPageToken != nil {
                    Button("Mehr laden") {
                        Task {
                            await session.loadWorkspaceOpportunities(query: query, order: sortMode,
                                timeWindow: session.opportunityTimeWindow,
                                contentFilter: session.opportunityContentFilter, loadMore: true)
                        }
                    }
                }
            }
            Text("Region: dort verfügbare Videos. Sprache: bevorzugte Treffer. Aufrufe und Datum sortieren die geladenen Videos; ‚Mehr laden‘ erweitert die Auswahl.")
                .font(.caption).foregroundStyle(.secondary)

            if let error = session.errorMessage {
                HStack(spacing: 12) {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    Spacer()
                    if error.localizedCaseInsensitiveContains("Google")
                        || error.localizedCaseInsensitiveContains("Berechtigung")
                        || error.localizedCaseInsensitiveContains("Kanal") {
                        Button("Google verbinden") {
                            session.showGoogleConnection = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Erneut versuchen") {
                            Task { await loadOpportunities() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }

            if session.opportunities.isEmpty {
                emptyState
            } else {
                opportunityContent
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .background(BlackstockDesign.canvas)
        .task {
            guard !hasLoadedInitially else { return }
            hasLoadedInitially = true
            await session.ensureYouTubeDiscoveryOptionsLoaded()
            if session.opportunities.isEmpty,
               session.workspaceChannelID != nil {
                await loadOpportunities()
            } else {
                selectedOpportunityID =
                    session.opportunities.first?.id
            }
        }
        .onChange(of: sortMode) { _ in
            guard hasLoadedInitially else { return }
            Task { await loadOpportunities() }
        }
        .onChange(of: session.opportunityTimeWindow) { _ in
            guard hasLoadedInitially else { return }
            Task { await loadOpportunities() }
        }
        .onChange(of: session.opportunityContentFilter) { _ in
            guard hasLoadedInitially else { return }
            Task { await loadOpportunities() }
        }
        .onChange(of: session.channelCategoryID) { categoryID in
            guard hasLoadedInitially else { return }
            if let category =
                    session.youtubeVideoCategories.first(
                        where: { $0.id == categoryID }
                    ) {
                session.primaryTopic = category.title
            }
            Task { await loadOpportunities() }
        }
        .onChange(of: session.channelRegionCode) { _ in
            guard hasLoadedInitially else { return }
            Task {
                await session.refreshYouTubeVideoCategories()
                await loadOpportunities()
            }
        }
        .onChange(of: session.contentLanguage) { _ in
            guard hasLoadedInitially else { return }
            Task {
                await session.refreshYouTubeVideoCategories()
                await loadOpportunities()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Entdecken")
                    .font(.largeTitle.bold())
                Text(
                    session.primaryTopic.isEmpty
                        ? "Finde ein Video und erstelle daraus einen Clip."
                        : "Kanal-Kategorie: \(session.primaryTopic) · Zeitraum: \(session.opportunityTimeWindow.germanTitle)"
                )
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        GroupBox {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(
                    session.workspaceChannelID == nil
                        ? "YouTube verbinden"
                        : "Noch keine passenden Videos"
                )
                    .font(.headline)
                Text(
                    session.workspaceChannelID == nil
                        ? "Verbinde dein Google-Konto und wähle anschließend den YouTube-Kanal, für den du recherchieren möchtest."
                        : "Suche nach einem Thema oder erweitere Zeitraum und Format. Blackstock zeigt echte YouTube-Treffer mit Aufrufen und Veröffentlichungsdatum."
                )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560)

                HStack(spacing: 10) {
                    if session.workspaceChannelID == nil {
                        Button("Google / YouTube verbinden") {
                            session.showGoogleConnection = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Erneut suchen") {
                            Task { await loadOpportunities() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Filter zurücksetzen") {
                            query = ""
                            session.opportunityContentFilter = .all
                            session.opportunityTimeWindow = .allTime
                            Task { await loadOpportunities() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private var opportunityContent: some View {
        HSplitView {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.opportunities) { item in
                        opportunityRow(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 280, idealWidth: 320)

            ScrollView {
                if let selectedOpportunity {
                    opportunityDetail(selectedOpportunity)
                        .padding(.leading, 18)
                } else {
                    Text("Wähle links ein Video aus.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .frame(minWidth: 360)
        }
    }

    private func opportunityRow(
        _ item: YouTubeOpportunityCandidate
    ) -> some View {
        Button {
            selectedOpportunityID = item.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: item.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                }
                .frame(width: 150, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Text(item.channelTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.contentKind.germanTitle.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.primary.opacity(0.07),
                                in: Capsule()
                            )
                    }

                    HStack(spacing: 10) {
                        if let views = item.metrics.viewCount {
                            Label(
                                compactNumber(views),
                                systemImage: "play.rectangle"
                            )
                        }
                        if let date = item.publishedAt {
                            Text(
                                date.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                )
                            )
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(
                selectedOpportunity?.id == item.id
                    ? BlackstockDesign.selectedFill
                    : BlackstockDesign.surface,
                in: RoundedRectangle(
                    cornerRadius: BlackstockDesign.cornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: BlackstockDesign.cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    selectedOpportunity?.id == item.id
                        ? BlackstockDesign.selectedBorder
                        : BlackstockDesign.subtleBorder
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func opportunityDetail(
        _ item: YouTubeOpportunityCandidate
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if item.embeddable != false {
                YouTubeEmbeddedPlayer(videoID: item.videoID)
                    .accessibilityLabel(
                        "YouTube-Vorschau: \(item.title)"
                    )
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .background(BlackstockDesign.mediaSurface)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: BlackstockDesign.cornerRadius,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: BlackstockDesign.cornerRadius,
                            style: .continuous
                        )
                        .strokeBorder(BlackstockDesign.subtleBorder)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.04))
                    VStack(spacing: 8) {
                        Image(systemName: "play.slash")
                            .font(.title)
                        Text("YouTube-Vorschau hier nicht verfügbar.")
                            .font(.headline)
                    }
                }
                .frame(minHeight: 260)
            }

            HStack {
                Spacer()
                Button("Auf YouTube ansehen") {
                    if let url = URL(
                        string:
                            "https://www.youtube.com/watch?v="
                            + item.videoID
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }

            Text(item.title)
                .font(.title2.bold())
                .textSelection(.enabled)
            Text(item.channelTitle)
                .foregroundStyle(.secondary)

            videoFacts(item)

            DisclosureGroup("Videodetails") {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        "Suchanfrage: \(item.query)",
                        systemImage: "magnifyingglass"
                    )
                    Label(
                        "Sortierung: \(sortMode.germanTitle)",
                        systemImage: "arrow.up.arrow.down"
                    )
                    Label(
                        "Abruf: "
                        + item.retrievedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        ),
                        systemImage: "clock.arrow.circlepath"
                    )

                    if !item.metrics.missingSignals.isEmpty {
                        Label(
                            "Einige Angaben sind bei YouTube für dieses Video nicht verfügbar.",
                            systemImage: "info.circle"
                        )
                    }

                    Text("Die Angaben stammen direkt von YouTube.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }

            if !session.workspaceRightsResponsibilityAccepted {
                GroupBox("Nutzungsrechte") {
                    Toggle(
                        isOn: Binding(
                            get: {
                                session.workspaceRightsResponsibilityAccepted
                            },
                            set: {
                                _ = session
                                    .setWorkspaceRightsResponsibilityAccepted(
                                        $0
                                    )
                            }
                        )
                    ) {
                        Text("Ich darf diesen Inhalt bearbeiten und veröffentlichen.")
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                }
            }

            if let active = session.activeProject {
                Label(
                    "„\(active.title)“ bleibt gespeichert, wenn du ein neues Projekt startest.",
                    systemImage: "tray.full"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    let previousID = session.activeProject?.id
                    session.useOpportunity(item)
                    if session.activeProject?.id != previousID {
                        onProjectCreated()
                    }
                } label: {
                    Label(
                        "Neues Projekt",
                        systemImage: "plus.rectangle.on.folder"
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    let previousID = session.activeProject?.id
                    session.useOpportunityAsClip(item)
                    if session.activeProject?.id != previousID {
                        onProjectCreated()
                    }
                } label: {
                    Label(
                        "Video schneiden",
                        systemImage: "scissors"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(BlackstockDesign.accent)
                .disabled(
                    !session.workspaceRightsResponsibilityAccepted
                )
            }
        }
    }

    private func videoFacts(
        _ item: YouTubeOpportunityCandidate
    ) -> some View {
        HStack(spacing: 8) {
            metricChip(
                "Format",
                item.contentKind.germanTitle,
                systemImage:
                    item.contentKind == .live
                    ? "dot.radiowaves.left.and.right"
                    : (
                        item.contentKind == .short
                        ? "rectangle.portrait"
                        : "play.rectangle"
                    )
            )
            if let durationSeconds = item.durationSeconds,
               item.contentKind != .live {
                metricChip(
                    "Dauer",
                    compactDuration(durationSeconds),
                    systemImage: "clock"
                )
            }
            if let views = item.metrics.viewCount {
                metricChip(
                    "Views",
                    compactNumber(views),
                    systemImage: "play.rectangle"
                )
            }
            if let likes = item.metrics.likeCount {
                metricChip(
                    "Likes",
                    compactNumber(likes),
                    systemImage: "hand.thumbsup"
                )
            }
            if let comments = item.metrics.commentCount {
                metricChip(
                    "Kommentare",
                    compactNumber(comments),
                    systemImage: "bubble.left"
                )
            }
        }
    }

    private func metricChip(
        _ title: String,
        _ value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(
                        .caption.weight(.semibold)
                            .monospacedDigit()
                    )
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private var selectedOpportunity:
        YouTubeOpportunityCandidate? {
        if let selectedOpportunityID,
           let selected = session.opportunities.first(
                where: { $0.id == selectedOpportunityID }
           ) {
            return selected
        }
        return session.opportunities.first
    }

    private func loadOpportunities() async {
        selectedOpportunityID = nil
        await session.loadWorkspaceOpportunities(
            query: query,
            order: sortMode,
            timeWindow: session.opportunityTimeWindow,
            contentFilter: session.opportunityContentFilter
        )
        selectedOpportunityID =
            session.opportunities.first?.id
    }

    private func compactDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes % 60,
                remainder
            )
        }
        return String(
            format: "%d:%02d",
            minutes,
            remainder
        )
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(
                format: "%.1fM",
                Double(value) / 1_000_000
            )
        }
        if value >= 1_000 {
            return String(
                format: "%.1fK",
                Double(value) / 1_000
            )
        }
        return String(value)
    }
}

struct ProjectLibraryView: View {
    @ObservedObject var session: BlackstockSession
    let onOpenProject: (BlackstockProject) -> Void
    let onFindOpportunity: () -> Void

    @State private var projectPendingDeletion:
        BlackstockProject?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projekte")
                        .font(.largeTitle.bold())
                    Text("Deine gespeicherten Projekte")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onFindOpportunity()
                } label: {
                    Label(
                        "Video finden",
                        systemImage: "sparkle.magnifyingglass"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            if session.projects.isEmpty {
                GroupBox {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Noch keine Projekte")
                            .font(.headline)
                        Text("Wähle unter „Videos“ ein Video aus und erstelle dein erstes Projekt.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Zu Videos") {
                            onFindOpportunity()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(session.projects) { project in
                            projectRow(project)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .confirmationDialog(
            "Projekt löschen?",
            isPresented: Binding(
                get: {
                    projectPendingDeletion != nil
                },
                set: { presented in
                    if !presented {
                        projectPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let project = projectPendingDeletion {
                Button(
                    "„\(project.title)“ löschen",
                    role: .destructive
                ) {
                    _ = session.deleteProject(project.id)
                    projectPendingDeletion = nil
                }
            }
            Button("Abbrechen", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: {
            Text(
                "Das Projekt und seine lokalen Schnitt-, Render- und Analysedaten werden von diesem Mac entfernt. Bereits auf YouTube veröffentlichte Videos werden nicht gelöscht."
            )
        }
    }

    private func projectRow(
        _ project: BlackstockProject
    ) -> some View {
        HStack(spacing: 14) {
            Image(
                systemName:
                    session.activeProject?.id == project.id
                    ? "folder.fill.badge.checkmark"
                    : "folder"
            )
            .font(.title2)
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.title)
                        .font(.headline)
                    if session.productionIntent(
                        for: project.id
                    )?.isLinkFirstClip == true {
                        Label(
                            "CLIP",
                            systemImage: "scissors"
                        )
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                    }
                    if project.isPaused {
                        Label(
                            "PAUSIERT",
                            systemImage: "pause.fill"
                        )
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                    }
                    if session.activeProject?.id == project.id {
                        Text("AKTIV")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.primary.opacity(0.07),
                                in: Capsule()
                            )
                    }
                }

                Text(project.stage.journeyGuidance.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let category =
                    session.projectChannelCategoryTitle(
                        for: project.id
                    ) {
                    Label(
                        "Kanal-Kategorie: \(category)",
                        systemImage: "tag"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(
                        "Kanal: \(project.targetChannelID)"
                    )
                    Text(
                        "Aktualisiert: "
                        + project.updatedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(
                    "Schritt \(project.stage.canonicalProgressPosition)/\(BlackstockStage.canonicalProgressCount)"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                ProgressView(
                    value: Double(
                        project.stage.canonicalProgressPosition
                    ),
                    total: Double(
                        BlackstockStage.canonicalProgressCount
                    )
                )
                .frame(width: 150)
                .tint(BlackstockDesign.accent)

                HStack(spacing: 8) {
                    if session.activeProject?.id == project.id {
                        Button {
                            onOpenProject(project)
                        } label: {
                            Label(
                                "Fortfahren",
                                systemImage: "arrow.right.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            onOpenProject(project)
                        } label: {
                            Label(
                                "Öffnen",
                                systemImage: "arrow.right.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Menu {
                        if project.stage != .published {
                            Button {
                                _ = session.setProjectPaused(
                                    project.id,
                                    paused: !project.isPaused
                                )
                            } label: {
                                Label(
                                    project.isPaused
                                        ? "Projekt fortsetzen"
                                        : "Projekt pausieren",
                                    systemImage:
                                        project.isPaused
                                        ? "play.fill"
                                        : "pause.fill"
                                )
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            projectPendingDeletion = project
                        } label: {
                            Label(
                                "Projekt löschen",
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel(
                        "Projektaktionen für \(project.title)"
                    )
                }
            }
        }
        .padding(14)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

struct ChannelAnalyticsWorkspaceView: View {
    @ObservedObject var session: BlackstockSession

    @State private var days = 28

    private let periods = [7, 28, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                channelIdentityCard

                if analyticsConnected {
                    periodMetrics
                    performanceDetails
                } else {
                    connectCard
                }

                if let error = session.errorMessage {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
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
            if analyticsConnected {
                await session.collectChannelAnalytics(
                    days: days
                )
            }
        }
        .onChange(of: days) { _ in
            guard analyticsConnected else { return }
            Task {
                await session.collectChannelAnalytics(
                    days: days
                )
            }
        }
    }

    private var analyticsConnected: Bool {
        guard let channelID =
                session.workspaceChannelID else {
            return false
        }
        return session.analyticsAuthorizedChannelID
            == channelID
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Analyse")
                    .font(.largeTitle.bold())
                Text(
                    "YouTube Studio-KPIs für deinen verbundenen Kanal"
                )
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if analyticsConnected {
                Picker(
                    "Zeitraum",
                    selection: $days
                ) {
                    ForEach(periods, id: \.self) {
                        Text("\($0) Tage").tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

                Button {
                    Task {
                        await session
                            .collectChannelAnalytics(
                                days: days
                            )
                    }
                } label: {
                    HStack {
                        if session.isCollectingAnalytics {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(
                            "Aktualisieren",
                            systemImage:
                                "arrow.clockwise"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    session.isCollectingAnalytics
                )
            }
        }
    }

    private var channelIdentityCard: some View {
        HStack(spacing: 18) {
            if let avatarURL =
                    session.workspaceChannel?.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(
                            Color.primary.opacity(0.08)
                        )
                }
                .frame(width: 68, height: 68)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(
                            Color.primary.opacity(0.08)
                        )
                    Image(systemName: "person.crop.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 68, height: 68)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(
                    session.workspaceChannel?.title
                    ?? "Verbundener YouTube-Kanal"
                )
                .font(.title2.bold())

                if let handle =
                        session.workspaceChannel?.handle,
                   !handle.isEmpty {
                    Text(handle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let channelID =
                        session.workspaceChannelID {
                    Text(channelID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if analyticsConnected {
                Label(
                    "Analytics verbunden",
                    systemImage:
                        "checkmark.seal.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .blackstockSurface(raised: true)
    }

    @ViewBuilder
    private var periodMetrics: some View {
        let channel = session.workspaceChannel
        let analytics = session.latestChannelAnalytics

        VStack(alignment: .leading, spacing: 12) {
            Text("Kanalübersicht")
                .font(.title2.bold())

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 180,
                            maximum: 260
                        ),
                        spacing: 12
                    )
                ],
                spacing: 12
            ) {
                metricCard(
                    title: "Abonnenten",
                    value: compactNumber(
                        channel?.subscriberCount
                    ),
                    systemImage: "person.2.fill"
                )
                metricCard(
                    title: "Gesamtviews",
                    value: compactNumber(
                        channel?.viewCount
                    ),
                    systemImage: "play.rectangle.fill"
                )
                metricCard(
                    title: "Videos",
                    value: compactNumber(
                        channel?.videoCount
                    ),
                    systemImage: "rectangle.stack.fill"
                )
                metricCard(
                    title: "Views · \(days) Tage",
                    value: compactNumber(
                        analytics?.views
                    ),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                metricCard(
                    title: "Netto-Abonnenten",
                    value: signedNumber(
                        analytics?.netSubscribers
                    ),
                    systemImage:
                        "person.badge.plus"
                )
                metricCard(
                    title: "Wiedergabezeit",
                    value: watchHours(
                        analytics?
                            .estimatedMinutesWatched
                    ),
                    systemImage: "clock.fill"
                )
            }

            if let analytics {
                Text(
                    analytics.startDate
                    + " – "
                    + analytics.endDate
                    + " · YouTube Analytics API"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var performanceDetails: some View {
        if let analytics =
                session.latestChannelAnalytics {
            VStack(alignment: .leading, spacing: 12) {
                Text("Performance")
                    .font(.title2.bold())

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(
                                minimum: 180,
                                maximum: 260
                            ),
                            spacing: 12
                        )
                    ],
                    spacing: 12
                ) {
                    metricCard(
                        title: "Likes",
                        value: compactNumber(
                            analytics.likes
                        ),
                        systemImage:
                            "hand.thumbsup.fill"
                    )
                    metricCard(
                        title: "Kommentare",
                        value: compactNumber(
                            analytics.comments
                        ),
                        systemImage:
                            "bubble.left.and.bubble.right.fill"
                    )
                    metricCard(
                        title: "Shares",
                        value: compactNumber(
                            analytics.shares
                        ),
                        systemImage: "arrowshape.turn.up.right.fill"
                    )
                    metricCard(
                        title: "Ø Wiedergabedauer",
                        value: duration(
                            analytics.averageViewDuration
                        ),
                        systemImage: "timer"
                    )
                    metricCard(
                        title: "Ø angesehen",
                        value: percentage(
                            analytics.averageViewPercentage
                        ),
                        systemImage: "percent"
                    )
                    metricCard(
                        title: "Engaged Views",
                        value: compactNumber(
                            analytics.engagedViews
                        ),
                        systemImage:
                            "eye.fill"
                    )
                }

                Text(
                    "YouTube Analytics kann zeitversetzt sein. Blackstock zeigt keine erfundenen Nullwerte, wenn YouTube für einen Zeitraum noch keine Daten liefert."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(
                    systemName:
                        "chart.bar.xaxis.ascending"
                )
                .font(.title2)
                .foregroundStyle(
                    BlackstockDesign.accent
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("YouTube Analytics verbinden")
                        .font(.headline)
                    Text(
                        "Lies Kanal- und Performance-KPIs direkt aus deinem verbundenen YouTube-Konto."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    await session.authorizeAnalytics()
                    if analyticsConnected {
                        await session
                            .collectChannelAnalytics(
                                days: days
                            )
                    }
                }
            } label: {
                HStack {
                    if session.isAuthorizingAnalytics {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        session.isAuthorizingAnalytics
                            ? "Google wird verbunden …"
                            : "Analytics aktivieren",
                        systemImage: "key.fill"
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isAuthorizingAnalytics)
        }
        .padding(20)
        .blackstockSurface(raised: true)
    }

    private func metricCard(
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
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 96,
            alignment: .leading
        )
        .padding(16)
        .blackstockSurface(raised: true)
    }

    private func compactNumber(
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

    private func signedNumber(
        _ value: Int?
    ) -> String {
        guard let value else { return "—" }
        return value > 0
            ? "+\(compactNumber(value))"
            : compactNumber(value)
    }

    private func watchHours(
        _ minutes: Double?
    ) -> String {
        guard let minutes else { return "—" }
        return String(
            format: "%.1f Std.",
            minutes / 60
        )
    }

    private func duration(
        _ seconds: Double?
    ) -> String {
        guard let seconds else { return "—" }
        let rounded = max(Int(seconds.rounded()), 0)
        return String(
            format: "%d:%02d",
            rounded / 60,
            rounded % 60
        )
    }

    private func percentage(
        _ value: Double?
    ) -> String {
        guard let value else { return "—" }
        return String(
            format: "%.1f%%",
            value
        )
    }
}

#endif
