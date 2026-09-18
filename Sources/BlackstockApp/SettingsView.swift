#if os(macOS)
import SwiftUI
import BlackstockCore

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @State private var region = ""
    @State private var showAccounts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einstellungen").font(.largeTitle.bold())
                    Text("Konten, Region und Datenschutz.").foregroundStyle(.secondary)
                }

                settingsSection("YouTube-Account", icon: "person.crop.circle.badge.checkmark") {
                    HStack(spacing: 14) {
                        ChannelAvatar(title: app.channel.title, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.channel.title).font(.headline)
                            Text(app.hasAuthenticatedChannel ? "Mit Google und YouTube verbunden" : "Kein YouTube-Kanal verbunden")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(app.hasAuthenticatedChannel ? "Accounts verwalten" : "YouTube verbinden") {
                            showAccounts = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blackstockRed)
                    }

                    if app.connectedChannels.count > 1 {
                        Divider()
                        Picker(
                            "Aktiver Kanal",
                            selection: Binding(
                                get: { app.channel.id },
                                set: { app.selectChannel(id: $0) }
                            )
                        ) {
                            ForEach(app.connectedChannels, id: \.id) { channel in
                                Text(channel.title).tag(channel.id)
                            }
                        }
                    }
                }

                settingsSection("Region", icon: "globe.europe.africa") {
                    TextField("Land oder Region, z. B. DE", text: $region)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveRegion() }

                    HStack {
                        Button("Übernehmen") { saveRegion() }
                        Text(app.regionCode.isEmpty ? "YouTube-Standard" : app.regionCode)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsSection("Datenschutz", icon: "hand.raised.fill") {
                    Text("Google-Passwörter werden nie in Blackstock gespeichert. Autorisierungstokens liegen im macOS-Schlüsselbund. Betreiber-Secrets und technische Provider-Konfiguration gehören nicht in die App.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if app.hasAuthenticatedChannel {
                        Button("Verbindungen verwalten") { showAccounts = true }
                    }
                }

                settingsSection("Blackstock", icon: "checkmark.shield") {
                    Text("Blackstock zeigt nur reale Daten und belegbare Zustände. Nicht validierte Funktionen bleiben im normalen Produkt unsichtbar.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(26)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: $showAccounts) {
            AccountConnectionSheet()
                .environmentObject(app)
                .environmentObject(auth)
        }
        .onAppear { region = app.regionCode }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.title3.bold())
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(16)
                .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    private func saveRegion() {
        app.regionCode = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
#endif
