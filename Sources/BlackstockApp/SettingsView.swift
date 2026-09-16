#if os(macOS)
import SwiftUI
import BlackstockCore

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Binding var apiKey: String
    @State private var draftKey = ""
    @State private var channelReference = ""
    @State private var region = ""
    @State private var isLoadingChannel = false
    @State private var channelMessage: String?

    var body: some View {
        Form {
            Section("Live-Daten") {
                SecureField("YouTube Data API Key", text: $draftKey)
                Text("Der API-Key wird im macOS-Schlüsselbund gespeichert und versorgt öffentliche Trends, Videos und Kanal-Baselines.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Speichern") { saveKey() }; Button("Entfernen") { draftKey = ""; Keychain.write("", account: "youtube-data-api-key"); apiKey = "" } }
            }
            Section("Dein Kanal") {
                TextField("@handle oder YouTube-Kanal-URL", text: $channelReference)
                HStack {
                    Button(isLoadingChannel ? "Kanal wird analysiert …" : "Öffentlichen Kanal analysieren") { loadChannel() }.disabled(isLoadingChannel || apiKey.isEmpty || channelReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isLoadingChannel { ProgressView().controlSize(.small) }
                }
                if app.channel.id != "local" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.channel.title).font(.headline)
                        Text("\(BlackstockFormat.compact(app.channel.subscriberCount)) Abonnenten · Median \(BlackstockFormat.compact(Int(app.channel.medianViews))) Views · \(Int(app.channel.medianViewsPerHour))/h").font(.caption).foregroundStyle(.secondary)
                        if !app.channel.recentTopics.isEmpty { Text("Themen: \(app.channel.recentTopics.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let channelMessage { Text(channelMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Trendregion") {
                TextField("ISO-Ländercode, z. B. DE — leer = YouTube Standard", text: $region).onSubmit { saveRegion() }
                Button("Region übernehmen") { saveRegion() }
            }
            Section("Produktprinzip") { Text("Blackstock zeigt keine künstlichen Chance-/Virality-Zahlen. Empfehlungen müssen durch konkrete Signale und reale Daten erklärbar sein.") }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .onAppear { draftKey = apiKey; region = app.regionCode }
    }

    private func saveKey() { let clean = draftKey.trimmingCharacters(in: .whitespacesAndNewlines); Keychain.write(clean, account: "youtube-data-api-key"); apiKey = clean }
    private func saveRegion() { app.regionCode = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    private func loadChannel() {
        let reference = channelReference
        isLoadingChannel = true; channelMessage = nil
        Task {
            do {
                let snapshot = try await YouTubeDataAPIClient(apiKey: apiKey).channelSnapshot(reference: reference)
                await MainActor.run { app.setChannel(snapshot); channelMessage = "Kanal-Baseline aus den letzten öffentlichen Uploads aktualisiert."; isLoadingChannel = false }
            } catch {
                await MainActor.run { channelMessage = error.localizedDescription; isLoadingChannel = false }
            }
        }
    }
}
#endif
