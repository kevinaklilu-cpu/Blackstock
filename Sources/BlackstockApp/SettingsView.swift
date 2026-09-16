#if os(macOS)
import SwiftUI
import BlackstockCore

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @Binding var apiKey: String
    @State private var draftKey = ""
    @State private var referenceChannel = ""
    @State private var region = ""
    @State private var isLoadingChannel = false
    @State private var channelMessage: String?
    @State private var showAccounts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einstellungen").font(.largeTitle.bold())
                    Text("Konten, Live-Daten und Arbeitsbereich.").foregroundStyle(.secondary)
                }

                settingsSection("YouTube-Account", icon: "person.crop.circle.badge.checkmark") {
                    HStack(spacing: 14) {
                        ChannelAvatar(title: app.channel.title, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.channel.title).font(.headline)
                            Text(app.hasAuthenticatedChannel ? "Mit Google/YouTube verbunden" : "Noch kein authentifizierter YouTube-Kanal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(app.hasAuthenticatedChannel ? "Accounts verwalten" : "YouTube verbinden") { showAccounts = true }
                            .buttonStyle(.borderedProminent).tint(.blackstockRed)
                    }
                    if app.connectedChannels.count > 1 {
                        Divider()
                        Picker("Aktiver Kanal", selection: Binding(get: { app.channel.id }, set: { app.selectChannel(id: $0) })) {
                            ForEach(app.connectedChannels, id: \.id) { channel in Text(channel.title).tag(channel.id) }
                        }
                    }
                }

                settingsSection("Öffentliche YouTube-Daten", icon: "bolt.horizontal.circle") {
                    SecureField("YouTube Data API Key", text: $draftKey).textFieldStyle(.roundedBorder)
                    Text("Der API-Key versorgt öffentliche Trends, Videos und Kanal-Baselines. Login-Tokens und API-Key bleiben getrennt im macOS-Schlüsselbund.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Speichern") { saveKey() }
                        Button("Entfernen") { draftKey = ""; Keychain.write("", account: "youtube-data-api-key"); apiKey = "" }
                            .foregroundStyle(.secondary)
                    }
                }

                settingsSection("Öffentlichen Kanal analysieren", icon: "scope") {
                    TextField("@handle oder YouTube-Kanal-URL", text: $referenceChannel).textFieldStyle(.roundedBorder)
                    Text("Das verbindet keinen Account. Es lädt nur öffentliche Vergleichsdaten für Research und Kanal-Baselines.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(isLoadingChannel ? "Wird analysiert …" : "Als aktive Analyse-Basis laden") { loadReferenceChannel() }
                            .disabled(isLoadingChannel || apiKey.isEmpty || referenceChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isLoadingChannel { ProgressView().controlSize(.small) }
                    }
                    if let channelMessage { Text(channelMessage).font(.caption).foregroundStyle(.secondary) }
                }

                settingsSection("Region", icon: "globe.europe.africa") {
                    TextField("ISO-Ländercode, z. B. DE — leer = YouTube Standard", text: $region)
                        .textFieldStyle(.roundedBorder).onSubmit { saveRegion() }
                    HStack { Button("Übernehmen") { saveRegion() }; Text(app.regionCode.isEmpty ? "YouTube Standard" : app.regionCode).font(.caption).foregroundStyle(.secondary) }
                }

                settingsSection("Blackstock", icon: "checkmark.shield") {
                    Text("Empfehlungen werden aus realen Signalen erklärt. Blackstock zeigt keine künstlichen Virality-Prozentwerte und speichert keine Google-Passwörter.")
                        .foregroundStyle(.secondary)
                    if app.onboardingSkipped { Button("Account-Onboarding wieder anzeigen") { app.showOnboardingAgain() } }
                }
            }
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showAccounts) { AccountConnectionSheet().environmentObject(app).environmentObject(auth) }
        .onAppear { draftKey = apiKey; region = app.regionCode }
    }

    private func settingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title3.bold())
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(16)
                .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    private func saveKey() {
        let clean = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.write(clean, account: "youtube-data-api-key")
        apiKey = clean
    }

    private func saveRegion() { app.regionCode = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    private func loadReferenceChannel() {
        let reference = referenceChannel
        isLoadingChannel = true; channelMessage = nil
        Task {
            do {
                let snapshot = try await YouTubeDataAPIClient(apiKey: apiKey).channelSnapshot(reference: reference)
                await MainActor.run {
                    app.setChannel(snapshot)
                    channelMessage = "Öffentliche Analyse-Basis auf \(snapshot.title) gesetzt."
                    isLoadingChannel = false
                }
            } catch {
                await MainActor.run { channelMessage = error.localizedDescription; isLoadingChannel = false }
            }
        }
    }
}
#endif
