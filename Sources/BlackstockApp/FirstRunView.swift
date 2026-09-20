#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct FirstRunView: View {
    @ObservedObject var session: BlackstockSession
    @State private var showOAuthImporter = false
    @State private var selectedOpportunityID: String?
    @State private var opportunitySortMode: OpportunitySortMode = .relevance

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            HStack(spacing: 0) {
                identityPane
                    .frame(minWidth: 390, idealWidth: 470, maxWidth: 540)
                Divider()
                contentPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fileImporter(
            isPresented: $showOAuthImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                session.importOAuthJSON(from: url)
            }
        }
    }

    private var identityPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            BlackstockWordmark(
                markWidth: 44,
                markHeight: 32,
                font: .title2
            )

            Spacer()

            Text("Von Video zu Clip.")
                .font(.system(size: 42, weight: .bold))
                .tracking(-1)
            Text("Verbinde deinen Kanal und starte.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(40)
        .background(Color.primary.opacity(0.025))
    }

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            stepHeader

            switch session.step {
            case .welcome:
                welcome
            case .channel:
                channelSelection
            case .topic:
                topic
            case .language:
                language
            case .preparing:
                preparing
            case .opportunities:
                opportunities
            }

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: 760)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(stepEyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(stepTitle)
                .font(.title.bold())
            Text(stepSubtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                Task { await session.connectGoogle() }
            } label: {
                HStack {
                    if session.isWorking {
                        ProgressView().controlSize(.small)
                    }
                    Text(
                        session.isWorking
                            ? "Google wird geöffnet …"
                            : "Mit Google verbinden"
                    )
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isWorking)

            HStack(spacing: 10) {
                Menu {
                    Button("Desktop-OAuth-JSON importieren …") {
                        showOAuthImporter = true
                    }
                    if session.hasImportedOAuthConfiguration {
                        Button(
                            "Importierte OAuth-Konfiguration entfernen",
                            role: .destructive
                        ) {
                            session.removeImportedOAuthConfiguration()
                        }
                    }
                } label: {
                    Label(
                        "OAuth-Konfiguration",
                        systemImage: "ellipsis.circle"
                    )
                }

                Text(session.oauthConfigurationSource)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var channelSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.channels) { channel in
                Button {
                    session.chooseChannel(channel.id)
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: channel.avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.primary.opacity(0.08))
                        }
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.title).font(.headline)
                            Text(channel.handle ?? channel.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topic: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "Thema, z. B. KI für Selbstständige",
                text: $session.primaryTopic
            )
            .accessibilityLabel("Kanalthema")
            .textFieldStyle(.roundedBorder)
            .font(.title3)

            TextField(
                "Content-Versprechen",
                text: $session.strategyContentPromise
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Zielgruppe",
                text: $session.strategyAudienceHypothesis
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Themenfelder, durch Komma getrennt",
                text: $session.strategyPillarsText
            )
            .textFieldStyle(.roundedBorder)

            DisclosureGroup("Weitere Optionen") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        "Angrenzende Themen",
                        text: $session.strategyAdjacentTopicsText
                    )
                    .textFieldStyle(.roundedBorder)

                    TextField(
                        "Ausgeschlossene Themen",
                        text: $session.strategyExcludedTopicsText
                    )
                    .textFieldStyle(.roundedBorder)

                    Picker(
                        "Ziel",
                        selection: $session.strategyObjective
                    ) {
                        Text("Ausgewogen").tag(StrategicObjective.balanced)
                        Text("Reichweite").tag(StrategicObjective.reach)
                        Text("Wiedergabezeit").tag(StrategicObjective.watchTime)
                        Text("Abonnenten").tag(StrategicObjective.subscribers)
                        Text("Umsatz").tag(StrategicObjective.revenue)
                    }
                    .pickerStyle(.menu)
                }
                .padding(.top, 8)
            }
            .font(.callout)

            HStack {
                Spacer()
                Button("Weiter") {
                    session.continueFromTopic()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var language: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Content-Sprache",
                selection: $session.contentLanguage
            ) {
                Text("Deutsch").tag("de")
                Text("Englisch").tag("en")
                Text("Spanisch").tag("es")
                Text("Französisch").tag("fr")
                Text("Italienisch").tag("it")
                Text("Portugiesisch").tag("pt")
            }
            .pickerStyle(.menu)

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
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nutzungsrechte bestätigt")
                        .font(.callout.weight(.semibold))
                    Text(
                        "Ich bearbeite und veröffentliche nur Inhalte, die ich verwenden darf."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack {
                Spacer()
                Button("Weiter") {
                    Task {
                        await session
                            .prepareChannelAndLoadOpportunities()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !session.workspaceRightsResponsibilityAccepted
                )
            }
        }
    }

    private var preparing: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kanal wird eingerichtet")
                        .font(.headline)
                    Text("YouTube-Daten werden geladen.")
                        .foregroundStyle(.secondary)
                }
            }

            if session.errorMessage != nil && !session.isWorking {
                Button("Erneut versuchen") {
                    Task {
                        await session
                            .prepareChannelAndLoadOpportunities()
                    }
                }
            }
        }
    }

    private var opportunities: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Videos")
                        .font(.headline)
                    Text("YouTube-Daten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sortierung", selection: $opportunitySortMode) {
                    ForEach(OpportunitySortMode.allCases, id: \.self) { mode in
                        Text(mode.germanTitle).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Opportunity-Sortierung")
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            if let selected = selectedOpportunity {
                VStack(alignment: .leading, spacing: 12) {
                    if selected.embeddable != false {
                        YouTubeEmbeddedPlayer(videoID: selected.videoID)
                            .accessibilityLabel("YouTube-Vorschau: \(selected.title)")
                            .frame(minHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.04))
                            VStack(spacing: 8) {
                                Image(systemName: "play.slash")
                                    .font(.title)
                                Text("YouTube-Vorschau hier nicht verfügbar.")
                                    .font(.callout.weight(.semibold))
                                Text("Für eine automatische Verarbeitung braucht Blackstock eine freigegebene Ingest-Quelle für diesen Link.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 260)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(selected.channelTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    signalStrip(selected)
                    explanationPanel(selected)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedOpportunities.prefix(8)) { item in
                        Button {
                            selectedOpportunityID = item.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: item.thumbnailURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(Color.primary.opacity(0.07))
                                }
                                .frame(width: 160, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 9))

                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .frame(width: 160, alignment: .leading)

                                HStack(spacing: 5) {
                                    if let views = item.metrics.viewCount {
                                        Text(compactNumber(views) + " Views")
                                    }
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(
                                selectedOpportunity?.id == item.id
                                    ? Color.accentColor.opacity(0.10)
                                    : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        selectedOpportunity?.id == item.id
                                            ? Color.accentColor.opacity(0.35)
                                            : Color.clear
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Spacer()

                if let selected = selectedOpportunity {
                    Button("Als Clip verwenden") {
                        session.useOpportunityAsClip(selected)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Blackstock öffnen") {
                        session.finishFirstRun()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onAppear {
            if selectedOpportunityID == nil {
                selectedOpportunityID = sortedOpportunities.first?.id
            }
        }
        .onChange(of: opportunitySortMode) { newMode in
            Task {
                selectedOpportunityID = nil
                await session.reloadOpportunities(order: newMode)
                selectedOpportunityID = session.opportunities.first?.id
            }
        }
    }

    @ViewBuilder
    private func signalStrip(_ item: YouTubeOpportunityCandidate) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let views = item.metrics.viewCount {
                    metricChip("Views", compactNumber(views), systemImage: "play.rectangle")
                }
                if let likes = item.metrics.likeCount {
                    metricChip("Likes", compactNumber(likes), systemImage: "hand.thumbsup")
                }
                if let comments = item.metrics.commentCount {
                    metricChip("Kommentare", compactNumber(comments), systemImage: "bubble.left")
                }
                if let date = item.publishedAt {
                    metricChip("Veröffentlicht", date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                }
            }
        }
    }

    private func metricChip(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }

    private func explanationPanel(_ item: YouTubeOpportunityCandidate) -> some View {
        DisclosureGroup("Warum wird dieses Video hier gezeigt?") {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Treffer der realen YouTube-Suche für „\(item.query)“.",
                    systemImage: "magnifyingglass"
                )
                Label(
                    "Aktuelle Sortierung: \(opportunitySortMode.germanTitle). \(opportunitySortMode.germanExplanation)",
                    systemImage: "arrow.up.arrow.down"
                )
                Label(
                    "Datenabruf: \(item.retrievedAt.formatted(date: .abbreviated, time: .shortened)).",
                    systemImage: "clock.arrow.circlepath"
                )

                if !item.metrics.missingSignals.isEmpty {
                    Label(
                        "Nicht verfügbar: " + item.metrics.missingSignals.joined(separator: ", ") + ". Blackstock ersetzt fehlende Werte nicht durch Schätzungen.",
                        systemImage: "info.circle"
                    )
                }

                Text("Blackstock zeigt hier nur von YouTube gelieferte Rohwerte. Die Reihenfolge wird über YouTubes offiziellen Search-Order-Parameter angefordert; Blackstock erzeugt daraus keinen eigenen Opportunity- oder Virality-Score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.semibold))
    }

    private var sortedOpportunities: [YouTubeOpportunityCandidate] {
        session.opportunities
    }

    private var selectedOpportunity: YouTubeOpportunityCandidate? {
        guard !sortedOpportunities.isEmpty else { return nil }
        if let selectedOpportunityID,
           let selected = sortedOpportunities.first(where: { $0.id == selectedOpportunityID }) {
            return selected
        }
        return sortedOpportunities.first
    }

    private func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return String(value)
    }


    private var stepEyebrow: String {
        switch session.step {
        case .welcome: "Schritt 1 von 6"
        case .channel: "Schritt 2 von 6"
        case .topic: "Schritt 3 von 6"
        case .language: "Schritt 4 von 6"
        case .preparing: "Schritt 5 von 6"
        case .opportunities: "Schritt 6 von 6"
        }
    }

    private var stepTitle: String {
        switch session.step {
        case .welcome: "Google verbinden"
        case .channel: "Kanal wählen"
        case .topic: "Kanal einrichten"
        case .language: "Sprache & Rechte"
        case .preparing: "Einrichtung"
        case .opportunities: "Video auswählen"
        }
    }

    private var stepSubtitle: String {
        switch session.step {
        case .welcome: "YouTube-Zugriff wird im Browser bestätigt."
        case .channel: "Wähle deinen YouTube-Kanal."
        case .topic: "Lege Thema und Zielgruppe fest."
        case .language: "Diese Angaben gelten für den Arbeitsbereich."
        case .preparing: "Einen Moment."
        case .opportunities: "Wähle ein Video oder öffne Blackstock."
        }
    }
}
#endif
