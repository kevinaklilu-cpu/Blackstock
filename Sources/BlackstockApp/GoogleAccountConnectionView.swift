#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct GoogleAccountConnectionView: View {
    @ObservedObject var session: BlackstockSession
    @Environment(\.dismiss) private var dismiss
    @State private var showConfigurationImporter = false
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                BlackstockBrandMark(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dein Kanal. Dein Studio.").font(.title2.bold())
                    Text("Google und YouTube mit Blackstock verbinden")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            GoogleConnectionCard(
                isReady: session.hasImportedOAuthConfiguration,
                isWorking: session.isWorking,
                importConfiguration: { showConfigurationImporter = true },
                signIn: { Task { await session.connectGoogle() } }
            )

            if !session.channels.isEmpty {
                Text("Deinen Kanal auswählen").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.channels) { channel in
                            Button {
                                Task { await session.useConnectedChannel(channel.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImage(url: channel.avatarURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "person.crop.circle.fill").font(.title)
                                    }
                                    .frame(width: 40, height: 40).clipShape(Circle())
                                    VStack(alignment: .leading) {
                                        Text(channel.title).font(.headline)
                                        Text(channel.handle ?? channel.id).font(.caption)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(10)
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.isWorking)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if let message = session.connectionStatusMessage {
                Text(message).font(.callout).textSelection(.enabled)
            }
            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Button {
                withAnimation { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("Erweiterte App-Einstellungen")
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showAdvanced {
                Button("Eigene Desktop-OAuth-JSON auswählen …") { showConfigurationImporter = true }
                    .disabled(session.isWorking)
                Text("Die App-Konfiguration legt keinen Kanal fest. Den Kanal wählst du erst nach der Google-Anmeldung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(session.isWorking ? "Anmeldung abbrechen" : "Schließen") {
                    session.cancelGoogleConnection()
                    dismiss()
                }
            }
        }
        .padding(28)
        }
        .frame(width: 620, height: 680)
        .fileImporter(isPresented: $showConfigurationImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result, session.importOAuthJSON(from: url) {
                session.connectionStatusMessage = "Google-Anmeldung ist vorbereitet. Du kannst dich jetzt anmelden."
            }
        }
    }
}
#endif
