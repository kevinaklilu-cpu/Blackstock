#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct FirstRunView: View {
    @ObservedObject var session: BlackstockSession
    @State private var showOAuthImporter = false
    @State private var selectedOpportunityID: String?
    @State private var opportunitySortMode: OpportunitySortMode = .views

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    BlackstockBrandMark(width: 46)
                    Text("Blackstock")
                        .font(.title2.bold())
                    Spacer()
                    Text("\(session.step.rawValue + 1) / 6")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 22)

                Divider()

                contentPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 880)
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
                BlackstockBrandMark(width: 46)
                Text("Blackstock").font(.title2.bold())
            }

            Spacer()

            Text("YouTube-Clips erstellen.")
                .font(.largeTitle.bold())
            Text("Kanal verbinden, Video auswählen, schneiden und veröffentlichen.")
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
                .font(.title.bold())
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
                    Image(systemName: "link")
                    Text(session.isWorking ? "Google wird verbunden …" : "Mit Google / YouTube anmelden")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isWorking)

            DisclosureGroup("Erweiterte App-Einstellungen") {
            Menu {
                Button("Eigene Desktop-OAuth-JSON auswählen …") {
                    showOAuthImporter = true
                }
                Button("Importierte OAuth-Konfiguration entfernen", role: .destructive) {
                    session.removeImportedOAuthConfiguration()
                }
            } label: {
                Label("OAuth-Datei importieren", systemImage: "doc.badge.gearshape")
            }

            Text(session.oauthConfigurationSource)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Die OAuth-Datei bleibt lokal. Zugangsdaten werden im macOS-Keychain gespeichert.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var channelSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(session.channels) { channel in
                Button {
                    Task {
                        await session.chooseChannel(channel.id)
                    }
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
        VStack(alignment: .leading, spacing: 16) {
            if session.isLoadingYouTubeSetupOptions {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Kanalinformationen werden geladen …")
                        .foregroundStyle(.secondary)
                }
            }

            Picker(
                "Land / Region",
                selection: $session.channelRegionCode
            ) {
                ForEach(session.youtubeRegions) { region in
                    Text(region.name).tag(region.code)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("YouTube-Region")
            .onChange(of: session.channelRegionCode) { _ in
                Task {
                    await session
                        .refreshYouTubeVideoCategories()
                }
            }

            Picker(
                "Content-Sprache",
                selection: $session.contentLanguage
            ) {
                ForEach(session.youtubeLanguages) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("YouTube-Content-Sprache")
            .onChange(of: session.contentLanguage) { _ in
                Task {
                    await session
                        .refreshYouTubeVideoCategories()
                }
            }

            Picker(
                "Video-Kategorie",
                selection: $session.channelCategoryID
            ) {
                ForEach(session.youtubeVideoCategories) { category in
                    Text(category.title).tag(category.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Video-Kategorie")

            Picker(
                "Trend-Zeitraum",
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
            .accessibilityLabel("Trend-Zeitraum")

            Picker(
                "Zielgruppe",
                selection: $session.channelAudienceSetting
            ) {
                ForEach(
                    YouTubeChannelAudienceSetting.allCases,
                    id: \.self
                ) { audience in
                    Text(audience.germanTitle).tag(audience)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("YouTube-Zielgruppe")

            Picker(
                "Hauptziel in Blackstock",
                selection: $session.strategyObjective
            ) {
                Text("Ausgewogen").tag(StrategicObjective.balanced)
                Text("Reichweite").tag(StrategicObjective.reach)
                Text("Wiedergabezeit").tag(StrategicObjective.watchTime)
                Text("Abonnenten").tag(StrategicObjective.subscribers)
                Text("Umsatz").tag(StrategicObjective.revenue)
            }
            .pickerStyle(.menu)

            Text(
                "Diese Auswahl steuert Blackstock für Suche, Schnitt und Veröffentlichung. Dein YouTube-Kanal wird dabei nicht automatisch verändert."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button {
                    Task {
                        await session.continueFromTopic()
                    }
                } label: {
                    if session.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            "Weiter",
                            systemImage: "checkmark.circle"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    session.isWorking
                    || session.isLoadingYouTubeSetupOptions
                    || session.channelRegionCode.isEmpty
                    || session.contentLanguage.isEmpty
                    || session.channelCategoryID.isEmpty
                )
            }
        }
    }

    private var language: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.officialChannelSettingsVerified {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "Blackstock-Profil gespeichert",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)

                    if session.channelAudienceAppliedToYouTube == false {
                        Text(
                            "Die Zielgruppe ist als Standard gespeichert und wird beim Veröffentlichen übernommen."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else if session.channelAudienceAppliedToYouTube == nil {
                        Text(
                            "Die Zielgruppe wird beim Veröffentlichen für jedes Video festgelegt."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

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
                    Text("Nutzungsrechte bestätigen")
                        .font(.callout.weight(.semibold))
                    Text("Ich darf die ausgewählten Inhalte bearbeiten und veröffentlichen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Text("Einmal pro Arbeitsbereich. Keine zusätzliche Lizenzdatei pro Video.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Videos laden") {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kanal wird vorbereitet").font(.headline)
                    Text(
                        "YouTube-Videos aus „\(session.primaryTopic)“ · \(session.opportunityTimeWindow.germanTitle) werden geladen."
                    )
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
                    Text("Videos")
                        .font(.headline)
                    Text("YouTube-Ergebnisse für deinen Kanal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
                .labelsHidden()
                .accessibilityLabel("Video-Zeitraum")
                .pickerStyle(.menu)
                .frame(maxWidth: 110)

                Picker("Sortierung", selection: $opportunitySortMode) {
                    ForEach(OpportunitySortMode.allCases, id: \.self) { mode in
                        Text(mode.germanTitle).tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Video-Sortierung")
                .pickerStyle(.menu)
                .frame(maxWidth: 160)
            }

            if let selected = selectedOpportunity {
                VStack(alignment: .leading, spacing: 12) {
                    if selected.embeddable != false {
                        YouTubeEmbeddedPlayer(videoID: selected.videoID)
                            .accessibilityLabel("YouTube-Vorschau: \(selected.title)")
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .background(BlackstockDesign.mediaSurface)
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
                                Text("Dieses Video kann hier nicht eingebettet abgespielt werden.")
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

                    videoFacts(selected)
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
                                    ? BlackstockDesign.selectedFill
                                    : BlackstockDesign.surface,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        selectedOpportunity?.id == item.id
                                            ? BlackstockDesign.selectedBorder
                                            : BlackstockDesign.subtleBorder
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Label("Video auswählen und als Clip öffnen", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onChange(of: session.opportunityTimeWindow) { _ in
            Task {
                selectedOpportunityID = nil
                await session.reloadOpportunities(
                    order: opportunitySortMode
                )
                selectedOpportunityID =
                    session.opportunities.first?.id
            }
        }
    }

    @ViewBuilder
    private func videoFacts(_ item: YouTubeOpportunityCandidate) -> some View {
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
                        "Für dieses Video sind einige Angaben bei YouTube nicht verfügbar.",
                        systemImage: "info.circle"
                    )
                }

                Text("Die Angaben stammen direkt von YouTube.")
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
        case .topic: "3 · Kanal"
        case .language: "4 · Rechte"
        case .preparing: "5 · Vorbereitung"
        case .opportunities: "6 · Video"
        }
    }

    private var stepTitle: String {
        switch session.step {
        case .welcome: "Mit Google / YouTube anmelden"
        case .channel: "YouTube-Kanal auswählen"
        case .topic: "Kanal einrichten"
        case .language: "Sprache und Rechte"
        case .preparing: "Kanal vorbereiten"
        case .opportunities: "Video auswählen"
        }
    }

    private var stepSubtitle: String {
        switch session.step {
        case .welcome: "Verknüpfe deinen YouTube-Kanal."
        case .channel: "Wähle den Kanal, mit dem du arbeiten willst."
        case .topic: "Wähle Region, Sprache, Kanal-Kategorie und Zielgruppe."
        case .language: "Bestätige die Nutzungsrechte für deinen Arbeitsbereich."
        case .preparing: "Blackstock lädt die benötigten Kanaldaten."
        case .opportunities: "Wähle ein Video für dein erstes Clip-Projekt."
        }
    }
}
#endif
