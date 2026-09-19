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
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08))
                    Text("B").font(.title2.bold())
                }
                .frame(width: 42, height: 42)
                Text("Blackstock").font(.title2.bold())
            }

            Spacer()

            Text("Vom Signal\nzum nächsten Video.")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.1)
            Text("Recherche, Produktion, Veröffentlichung und echtes Lernen aus deinem YouTube-Kanal – mit nachvollziehbaren Quellen statt erfundenen Scores.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Label("Produktsprache Deutsch · Content-Sprache separat", systemImage: "character.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(36)
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
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(stepSubtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                Task { await session.connectGoogle() }
            } label: {
                HStack {
                    if session.isWorking { ProgressView().controlSize(.small) }
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text(session.isWorking ? "Warte auf Google …" : "Mit Google fortfahren")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isWorking)

            Menu {
                Button("Eigene Desktop-OAuth-JSON auswählen …") {
                    showOAuthImporter = true
                }
                Button("Importierte OAuth-Konfiguration entfernen", role: .destructive) {
                    session.removeImportedOAuthConfiguration()
                }
            } label: {
                Label("Verbindungsoptionen", systemImage: "ellipsis.circle")
            }

            Text("OAuth-Konfiguration: \(session.oauthConfigurationSource)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Eine importierte Google-JSON wird lokal validiert. Blackstock übernimmt nur die Desktop-Client-ID; ein enthaltenes Client Secret wird nicht benötigt und nicht gespeichert.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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
            Text("Blackstock wählt keinen Kanal stillschweigend aus.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var topic: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(
                    "Kanal-Schwerpunkt, z. B. KI für Selbstständige",
                    text: $session.primaryTopic
                )
                .accessibilityLabel("Strategischer Kanal-Schwerpunkt")
                .textFieldStyle(.roundedBorder)
                .font(.title3)

                TextField(
                    "Was gehört konkret zu diesem Thema?",
                    text: $session.topicDefinition
                )
                .accessibilityLabel("Definition des Kanalthemas")
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Welches konkrete Versprechen gibst du den Zuschauern?",
                    text: $session.contentPromise
                )
                .accessibilityLabel("Versprechen an die Zuschauer")
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Für wen ist der Kanal hauptsächlich gedacht?",
                    text: $session.audienceHypothesis
                )
                .accessibilityLabel("Zielgruppen-Hypothese")
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Inhaltssäulen, durch Kommas getrennt",
                    text: $session.strategyPillars
                )
                .accessibilityLabel("Wiederkehrende Inhaltssäulen")
                .textFieldStyle(.roundedBorder)

                Picker(
                    "Primäres strategisches Ziel",
                    selection: $session.strategicObjective
                ) {
                    ForEach(StrategicObjective.allCases, id: \.self) { objective in
                        Text(objective.germanTitle).tag(objective)
                    }
                }
                .pickerStyle(.menu)

                DisclosureGroup("Optionale strategische Grenzen") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(
                            "Angrenzende Themen, optional",
                            text: $session.adjacentTopics
                        )
                        .textFieldStyle(.roundedBorder)

                        TextField(
                            "Ausgeschlossene Themen, optional",
                            text: $session.excludedTopics
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 8)
                }

                Text(
                    "Blackstock speichert nur deine Angaben. Versprechen, Zielgruppe und Inhaltssäulen werden nicht aus dem Kanalthema erfunden."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Weiter") {
                        session.continueFromTopic()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var language: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Primäre Content-Sprache", selection: $session.contentLanguage) {
                Text("Deutsch").tag("de")
                Text("Englisch").tag("en")
                Text("Spanisch").tag("es")
                Text("Französisch").tag("fr")
                Text("Italienisch").tag("it")
                Text("Portugiesisch").tag("pt")
            }
            .pickerStyle(.menu)

            Text("Blackstock selbst bleibt Deutsch. Research-Sprachen können später breiter sein als die Output-Sprache.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Kanal vorbereiten") {
                    Task { await session.prepareChannelAndLoadOpportunities() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var preparing: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Strategie wird versioniert gespeichert").font(.headline)
                    Text("Danach lädt Blackstock reale YouTube-Kandidaten für „\(session.primaryTopic)“.")
                        .foregroundStyle(.secondary)
                }
            }
            if session.errorMessage != nil && !session.isWorking {
                Button("Erneut versuchen") {
                    Task { await session.prepareChannelAndLoadOpportunities() }
                }
            }
        }
    }

    private var opportunities: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reale YouTube-Signale")
                        .font(.headline)
                    Text("Rohdaten von YouTube · keine abgeleiteten Scores")
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
                Label("Ansehen → verstehen → als Projekt übernehmen", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if let selected = selectedOpportunity {
                    Button("Als Clip verwenden") {
                        session.useOpportunity(selected)
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
        case .welcome: "1 · Google"
        case .channel: "2 · YouTube-Kanal"
        case .topic: "3 · Kanalthema"
        case .language: "4 · Content-Sprache"
        case .preparing: "5 · Vorbereitung"
        case .opportunities: "6 · Erste Chancen"
        }
    }

    private var stepTitle: String {
        switch session.step {
        case .welcome: "Willkommen bei Blackstock"
        case .channel: "Welcher Kanal ist dein Arbeitsbereich?"
        case .topic: "Wofür soll dein Kanal stehen?"
        case .language: "Sprache deiner Inhalte"
        case .preparing: "Blackstock bereitet deinen Kanal vor"
        case .opportunities: "Deine ersten Chancen"
        }
    }

    private var stepSubtitle: String {
        switch session.step {
        case .welcome: "Google öffnet im Systembrowser. Blackstock fordert zunächst nur Leserechte für YouTube an."
        case .channel: "Wähle den konkreten Zielkanal explizit aus."
        case .topic: "Lege Thema, Versprechen, Zielgruppe und wiederkehrende Inhaltssäulen ausdrücklich fest."
        case .language: "Produkt- und Content-Sprache sind unterschiedliche Einstellungen."
        case .preparing: "Nur reale, verfügbare Daten werden verarbeitet."
        case .opportunities: "Diese Liste stammt aus der realen YouTube-API und ist noch keine automatisch behauptete Empfehlung."
        }
    }
}
#endif
