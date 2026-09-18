#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import BlackstockCore

struct FirstRunView: View {
    @ObservedObject var session: BlackstockSession
    @State private var showOAuthImporter = false
    @State private var selectedOpportunityID: String?

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
            Text("Research, Produktion, Publishing und echtes Lernen aus deinem YouTube-Kanal – mit nachvollziehbaren Quellen statt erfundenen Scores.")
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
        VStack(alignment: .leading, spacing: 14) {
            TextField("z. B. KI für Selbstständige", text: $session.primaryTopic)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            Text("Das ist der strategische Kern für künftige Research- und Opportunity-Abfragen, nicht nur ein einzelnes Suchkeyword.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Weiter") { session.continueFromTopic() }
                    .buttonStyle(.borderedProminent)
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
            Text("Reale YouTube-Ergebnisse · noch keine Blackstock-Bewertung")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selected = selectedOpportunity {
                VStack(alignment: .leading, spacing: 10) {
                    YouTubeEmbeddedPlayer(videoID: selected.videoID)
                        .frame(minHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(selected.channelTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Label("YouTube API", systemImage: "checkmark.seal")
                            Text("Query: \(selected.query)")
                            Text("Abruf: \(selected.retrievedAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(session.opportunities.prefix(8)) { item in
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
                            }
                            .padding(8)
                            .background(
                                selectedOpportunity?.id == item.id
                                    ? Color.accentColor.opacity(0.10)
                                    : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Ansehen → verstehen → erst dann übernehmen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Blackstock öffnen") { session.finishFirstRun() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            if selectedOpportunityID == nil {
                selectedOpportunityID = session.opportunities.first?.id
            }
        }
    }

    private var selectedOpportunity: YouTubeOpportunityCandidate? {
        guard !session.opportunities.isEmpty else { return nil }
        if let selectedOpportunityID,
           let selected = session.opportunities.first(where: { $0.id == selectedOpportunityID }) {
            return selected
        }
        return session.opportunities.first
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
        case .channel: "Welcher Kanal ist dein Workspace?"
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
        case .topic: "Lege den strategischen Kern fest. Historische Beobachtungen bleiben davon getrennt."
        case .language: "Produkt- und Content-Sprache sind unterschiedliche Einstellungen."
        case .preparing: "Nur reale, verfügbare Daten werden verarbeitet."
        case .opportunities: "Diese Liste stammt aus der realen YouTube-API und ist noch keine automatisch behauptete Empfehlung."
        }
    }
}
#endif
