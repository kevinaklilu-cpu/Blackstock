#if os(macOS)
import SwiftUI
import BlackstockCore

struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var auth: GoogleYouTubeAuth
    @State private var clientID = GoogleYouTubeAuth.configuredClientID
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 26) {
                    BlackstockBrandLockup()
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Dein YouTube-Workflow.\nEin Kanal. Ein System.")
                            .font(.system(size: min(max(proxy.size.width * 0.038, 38), 60), weight: .bold, design: .rounded))
                            .tracking(-1.3)
                        Text("Verbinde deinen Kanal einmal. Danach gehören Trends, Ideen, Projekte, Publishing und Analytics immer zum richtigen Creator-Workspace.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 620, alignment: .leading)
                    }

                    HStack(spacing: 18) {
                        feature("flame.fill", "Trends", "auf deinen Kanal bezogen")
                        feature("timeline.selection", "Studio", "Projekte direkt zugeordnet")
                        feature("chart.xyaxis.line", "Analytics", "pro Kanal getrennt")
                    }
                    Spacer()
                    Text("Blackstock speichert keine Google-Passwörter. Die Anmeldung läuft über Google im Systembrowser.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    ZStack {
                        Color.blackstockSurface
                        RadialGradient(colors: [Color.blackstockRed.opacity(0.12), .clear], center: .topLeading, startRadius: 20, endRadius: 650)
                    }
                )

                VStack(alignment: .leading, spacing: 20) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        BlackstockBrandMark(size: 42)
                        Text("Bei Blackstock anmelden").font(.title.bold())
                        Text("Mit YouTube verbinden, damit Blackstock deinen Kanal erkennt und neue Videos dem richtigen Workspace zuordnet.")
                            .foregroundStyle(.secondary)
                    }

                    if GoogleYouTubeAuth.configuredClientID.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Entwicklungs-Build").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("Google Desktop OAuth Client-ID", text: $clientID)
                                .textFieldStyle(.roundedBorder)
                            Text("Im final paketierten Build wird diese ID automatisch mitgeliefert.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }

                    Button(action: connect) {
                        HStack(spacing: 10) {
                            if auth.isConnecting { ProgressView().controlSize(.small) }
                            Image(systemName: "play.rectangle.fill")
                            Text(auth.isConnecting ? "YouTube wird verbunden …" : "Mit YouTube verbinden")
                                .fontWeight(.semibold)
                            Spacer()
                            if !auth.isConnecting { Image(systemName: "arrow.right") }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(Color.blackstockRed, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isConnecting)

                    if let status = auth.statusMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }

                    Divider()
                    Button("Ohne Kanal ansehen") { app.continueWithoutAccount() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Text("Du kannst den YouTube-Account später jederzeit über den Kanal-Switcher verbinden.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(36)
                .frame(width: min(max(proxy.size.width * 0.34, 390), 500), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.blackstockRed)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: 180, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func connect() {
        errorMessage = nil
        let clean = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { Keychain.write(clean, account: "youtube-oauth-client-id") }
        Task {
            do {
                let session = try await auth.connect(clientID: clean.isEmpty ? nil : clean)
                app.addConnectedChannels(session.channels)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
#endif
