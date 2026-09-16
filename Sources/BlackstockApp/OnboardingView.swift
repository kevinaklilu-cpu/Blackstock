#if os(macOS)
import SwiftUI
import AppKit
import BlackstockCore

struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @State private var clientID = GoogleYouTubeAuth.configuredClientID
    @State private var errorMessage: String?
    @State private var showAdvanced = GoogleYouTubeAuth.configuredClientID.isEmpty
    @State private var glow = false

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                brandPane(proxy: proxy)
                loginPane
                    .frame(width: min(max(proxy.size.width * 0.36, 420), 520))
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Color.blackstockSurface)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    private func brandPane(proxy: GeometryProxy) -> some View {
        ZStack {
            Color.blackstockSurface
            RadialGradient(
                colors: [Color.blackstockRed.opacity(glow ? 0.18 : 0.08), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: glow ? 760 : 620
            )
            VStack(alignment: .leading, spacing: 26) {
                BlackstockBrandLockup()
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Dein Kanal.\nDein Creator-System.")
                        .font(.system(size: min(max(proxy.size.width * 0.040, 42), 64), weight: .bold, design: .rounded))
                        .tracking(-1.5)
                    Text("Von Trends über Produktion bis zum Upload – Blackstock hält jeden Schritt im Kontext des richtigen YouTube-Kanals.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 650, alignment: .leading)
                }

                HStack(spacing: 12) {
                    feature("flame.fill", "Entdecken", "Signale & Nischen")
                    feature("timeline.selection", "Produzieren", "Schnitt & Reframe")
                    feature("arrow.up.circle.fill", "Publizieren", "Direkt zum Kanal")
                    feature("chart.xyaxis.line", "Lernen", "Performance")
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                    Text("Google-Passwörter werden nie in Blackstock gespeichert. Tokens liegen im macOS-Schlüsselbund.")
                }
                .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(44)
        }
    }

    private var loginPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                BlackstockBrandMark(size: 46)
                Text("YouTube verbinden").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Einmal anmelden, Kanal auswählen und danach Trends, Projekte, Uploads und Analytics automatisch zuordnen.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                authStep(number: "1", title: "Google-Account", subtitle: "Anmeldung im Systembrowser")
                Divider().padding(.leading, 48)
                authStep(number: "2", title: "YouTube-Kanal", subtitle: "Blackstock erkennt deine Kanäle")
                Divider().padding(.leading, 48)
                authStep(number: "3", title: "Workspace", subtitle: "Alles wird dem aktiven Kanal zugeordnet")
            }
            .background(Color.blackstockPanel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.blackstockBorder))

            if auth.isConnecting {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(auth.statusMessage ?? "Google-Anmeldung läuft …").font(.subheadline.weight(.medium))
                    }
                    if let hint = auth.callbackHint { Text(hint).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                    HStack {
                        Text("Das Browserfenster abschließen; Blackstock übernimmt danach automatisch.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Abbrechen") { auth.cancelConnection() }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.blackstockRed.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.blackstockRed.opacity(0.16)))
            }

            Button(action: connect) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text(auth.isConnecting ? "Warte auf Google …" : "Mit YouTube verbinden").fontWeight(.semibold)
                    Spacer()
                    if !auth.isConnecting { Image(systemName: "arrow.right") }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Color.blackstockRed, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: Color.blackstockRed.opacity(0.22), radius: 15, y: 7)
            }
            .buttonStyle(.plain)
            .disabled(auth.isConnecting)

            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Desktop OAuth Client-ID (…apps.googleusercontent.com)", text: $clientID)
                        .textFieldStyle(.roundedBorder)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Color.blackstockRed)
                        Text("Kein Client Secret nötig. Blackstock ist eine installierte Desktop-App und verwendet PKCE mit lokalem Loopback-Callback. Wenn Google dir vor allem ein Client Secret anbietet, prüfe, ob du versehentlich einen „Web application“-Client statt „Desktopanwendung“ erstellt hast.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Google OAuth-Anleitung öffnen") {
                        if let url = URL(string: "https://developers.google.com/youtube/v3/guides/auth/installed-apps") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link)
                }
                .padding(.top, 10)
            } label: {
                Text(GoogleYouTubeAuth.configuredClientID.isEmpty ? "OAuth konfigurieren" : "OAuth-Konfiguration")
                    .font(.subheadline.weight(.semibold))
            }

            if let status = auth.statusMessage, !auth.isConnecting { Text(status).font(.caption).foregroundStyle(.secondary) }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack {
                Button("Ohne Account ansehen") { app.continueWithoutAccount() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("macOS 13+").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(36)
        .background(.ultraThinMaterial)
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.blackstockRed)
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

    private func connect() {
        errorMessage = nil
        let clean = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { Keychain.write(clean, account: "youtube-oauth-client-id") }
        Task {
            do {
                let session = try await auth.connect(clientID: clean.isEmpty ? nil : clean)
                app.addConnectedChannels(session.channels)
            } catch is CancellationError {
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                showAdvanced = true
            }
        }
    }
}
#endif
