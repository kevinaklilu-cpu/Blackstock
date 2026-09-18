#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BlackstockCore

struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth

    private enum Step {
        case google
        case channel
        case topic
        case language
        case calibration
    }

    @State private var step: Step = .google
    @State private var selectedChannelID: String?
    @State private var topic = ""
    @State private var contentLanguage = "de"
    @State private var errorMessage: String?
    @State private var glow = false

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                brandPane(proxy: proxy)
                stepPane
                    .frame(width: min(max(proxy.size.width * 0.38, 440), 560))
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color.blackstockSurface)
        .onAppear {
            resumeStep()
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }

    private func brandPane(proxy: GeometryProxy) -> some View {
        ZStack {
            Color.blackstockSurface
            RadialGradient(
                colors: [Color.blackstockRed.opacity(glow ? 0.16 : 0.07), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: glow ? 760 : 620
            )

            VStack(alignment: .leading, spacing: 26) {
                BlackstockBrandLockup()
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Von der Chance\nbis zur nächsten Entscheidung.")
                        .font(.system(size: min(max(proxy.size.width * 0.040, 42), 64), weight: .bold, design: .rounded))
                        .tracking(-1.5)
                    Text("Blackstock verbindet Research, Produktion, Publishing und echte YouTube-Ergebnisse in einem nachvollziehbaren Creator-Workflow.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 660, alignment: .leading)
                }

                HStack(spacing: 12) {
                    feature("scope", "Verstehen", "Evidence statt Vermutung")
                    feature("lightbulb.fill", "Entscheiden", "Warum + nächste Aktion")
                    feature("timeline.selection", "Produzieren", "Reversibel bearbeiten")
                    feature("chart.xyaxis.line", "Lernen", "Reale Ergebnisse")
                }

                Spacer()

                Label(
                    "Google-Passwörter werden nie in Blackstock gespeichert. Tokens liegen im macOS-Schlüsselbund.",
                    systemImage: "lock.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(44)
        }
    }

    @ViewBuilder
    private var stepPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            progressHeader

            switch step {
            case .google:
                googleStep
            case .channel:
                channelStep
            case .topic:
                topicStep
            case .language:
                languageStep
            case .calibration:
                calibrationStep
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(36)
        .background(.ultraThinMaterial)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlackstockBrandMark(size: 44)
            Text(stepTitle)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(stepSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var googleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                authStep(number: "1", title: "Google-Konto", subtitle: "Explizite Auswahl im Systembrowser")
                Divider().padding(.leading, 48)
                authStep(number: "2", title: "YouTube-Kanal", subtitle: "Du wählst den konkreten Zielkanal")
                Divider().padding(.leading, 48)
                authStep(number: "3", title: "Ausrichtung", subtitle: "Thema und Content-Sprache")
            }
            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))

            if auth.isConnecting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(auth.statusMessage ?? "Google-Anmeldung läuft …")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Abbrechen") { auth.cancelConnection() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.blackstockRed.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }

            Button(action: connect) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text(auth.isConnecting ? "Warte auf Google …" : "Mit Google fortfahren")
                        .fontWeight(.semibold)
                    Spacer()
                    if !auth.isConnecting { Image(systemName: "arrow.right") }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.blackstockRed, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .disabled(auth.isConnecting)

            Menu {
                Button("Eigene OAuth-JSON auswählen …") {
                    importOAuthJSON()
                }
                if !GoogleYouTubeAuth.importedClientID.isEmpty {
                    Button("Eigene OAuth-Konfiguration entfernen", role: .destructive) {
                        auth.removeImportedOAuthConfiguration()
                    }
                }
            } label: {
                Label("Verbindungsoptionen", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)

            Text("Standard: vorkonfigurierte Blackstock-Anmeldung. Optional kannst du eine eigene Google-OAuth-JSON vom Typ „Desktopanwendung“ verwenden. Blackstock übernimmt daraus nur die Client-ID; ein enthaltenes Client Secret wird weder benötigt noch gespeichert.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var channelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcher Kanal soll dieser Blackstock-Arbeitsbereich sein?")
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(app.connectedChannels, id: \.id) { channel in
                        Button {
                            selectedChannelID = channel.id
                        } label: {
                            HStack(spacing: 12) {
                                channelAvatar(channel)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(channel.title)
                                        .font(.headline)
                                    Text(channel.handle ?? "YouTube-Kanal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedChannelID == channel.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.blackstockRed)
                                }
                            }
                            .padding(12)
                            .background(
                                selectedChannelID == channel.id
                                    ? Color.blackstockRed.opacity(0.08)
                                    : Color.blackstockPanel,
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13)
                                    .strokeBorder(
                                        selectedChannelID == channel.id
                                            ? Color.blackstockRed.opacity(0.35)
                                            : Color.blackstockBorder
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)

            HStack {
                Button("Zurück") { step = .google }
                Spacer()
                Button("Weiter") {
                    guard let selectedChannelID else { return }
                    app.selectChannel(id: selectedChannelID)
                    step = .topic
                }
                .buttonStyle(.borderedProminent)
                .tint(.blackstockRed)
                .disabled(selectedChannelID == nil)
            }
        }
    }

    private var topicStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wofür soll dein Kanal stehen?")
                .font(.headline)
            Text("Beschreibe den strategischen Kern in normaler Sprache. Das ist kein einzelnes Keyword.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("z. B. KI für Selbstständige", text: $topic)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            HStack {
                Button("Zurück") { step = .channel }
                Spacer()
                Button("Weiter") { step = .language }
                    .buttonStyle(.borderedProminent)
                    .tint(.blackstockRed)
                    .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sprache deiner Inhalte bestätigen")
                .font(.headline)
            Text("Die Produktsprache von Blackstock bleibt Deutsch. Diese Auswahl steuert die Sprache deiner Inhalte und ist davon unabhängig.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Primäre Content-Sprache", selection: $contentLanguage) {
                Text("Deutsch").tag("de")
                Text("Englisch").tag("en")
                Text("Spanisch").tag("es")
                Text("Französisch").tag("fr")
                Text("Italienisch").tag("it")
                Text("Portugiesisch").tag("pt")
            }
            .pickerStyle(.menu)

            HStack {
                Button("Zurück") { step = .topic }
                Spacer()
                Button("Kanal vorbereiten") {
                    guard let selectedChannelID else { return }
                    app.completeFirstRun(
                        channelID: selectedChannelID,
                        primaryTopic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
                        contentLanguage: contentLanguage
                    )
                    step = .calibration
                }
                .buttonStyle(.borderedProminent)
                .tint(.blackstockRed)
            }
        }
    }

    private var calibrationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Blackstock bereitet deinen Kanal vor", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundStyle(Color.blackstockRed)

            calibrationRow("Kanalidentität", detail: app.channel.title, passed: app.channel.id != "local")
            calibrationRow(
                "Google-Autorisierung",
                detail: "YouTube lesen",
                passed: GoogleYouTubeAuth.hasScopes([.youtubeReadOnly], channelID: app.channel.id)
            )
            calibrationRow(
                "Strategischer Anker",
                detail: app.activeStrategy?.primaryTopic ?? "",
                passed: app.activeStrategy != nil
            )
            calibrationRow(
                "Content-Sprache",
                detail: app.activeStrategy?.defaultContentLanguage.uppercased() ?? "",
                passed: app.activeStrategy != nil
            )

            Text("Weitere Kalibrierung wie Analytics-Baseline, Umsatzprofil oder Kommentar-Signale wird nur aktiviert, wenn die dafür erforderliche reale Capability und Berechtigung vorhanden ist.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Deine ersten Chancen") {
                app.finishFirstRun(channelID: app.channel.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blackstockRed)
            .disabled(app.activeStrategy == nil)
        }
    }

    private func channelAvatar(_ channel: ChannelSnapshot) -> some View {
        Group {
            if let url = channel.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ChannelAvatar(title: channel.title, size: 42)
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                ChannelAvatar(title: channel.title, size: 42)
            }
        }
    }

    private func calibrationRow(_ title: String, detail: String, passed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(passed ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.blackstockRed)
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: 155, alignment: .leading)
        .background(Color.primary.opacity(0.034), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.055)))
    }

    private func authStep(number: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blackstockRed.opacity(0.11)).frame(width: 28, height: 28)
                Text(number).font(.caption.weight(.bold)).foregroundStyle(Color.blackstockRed)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private func resumeStep() {
        if app.connectedChannels.isEmpty {
            step = .google
            return
        }

        if app.channel.id == "local" {
            step = .channel
            return
        }

        selectedChannelID = app.channel.id
        if app.activeStrategy == nil {
            step = .topic
        } else {
            topic = app.activeStrategy?.primaryTopic ?? ""
            contentLanguage = app.activeStrategy?.defaultContentLanguage ?? "de"
            step = .calibration
        }
    }

    private func connect() {
        errorMessage = nil
        Task {
            do {
                let session = try await auth.connect(requiredScopes: [.youtubeReadOnly])
                app.addConnectedChannels(session.channels)
                selectedChannelID = nil
                step = .channel
            } catch is CancellationError {
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importOAuthJSON() {
        let panel = NSOpenPanel()
        panel.title = "Google OAuth-JSON auswählen"
        panel.message = "Wähle die von Google für eine Desktopanwendung exportierte OAuth-JSON-Datei."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let config = try auth.importDesktopOAuthJSON(from: url)
            errorMessage = nil
            auth.statusMessage = "Eigene OAuth-Konfiguration bereit: \(config.projectID ?? "Google-Projekt")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var stepTitle: String {
        switch step {
        case .google: return "Willkommen bei Blackstock"
        case .channel: return "YouTube-Kanal auswählen"
        case .topic: return "Kanal ausrichten"
        case .language: return "Content-Sprache"
        case .calibration: return "Kanal vorbereitet"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .google:
            return "Verbinde Google sicher und wähle danach bewusst den YouTube-Kanal, mit dem du arbeiten möchtest."
        case .channel:
            return "Blackstock übernimmt keinen Kanal stillschweigend."
        case .topic:
            return "Definiere, wofür dein Kanal künftig stehen soll."
        case .language:
            return "Research kann später mehrsprachig sein; deine primäre Output-Sprache bleibt davon getrennt."
        case .calibration:
            return "Nur verfügbare und belegte Fähigkeiten werden aktiviert."
        }
    }
}
#endif
