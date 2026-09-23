#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct GoogleAccountConnectionView: View {
    @ObservedObject var session: BlackstockSession
    @Environment(\.dismiss) private var dismiss
    @State private var showConfigurationImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Google und YouTube verbinden").font(.title2.bold())
            Text("Melde dich bei Google an. Danach wählst du den YouTube-Kanal, mit dem du in Blackstock arbeiten möchtest.")
                .foregroundStyle(.secondary)
            Button {
                Task { await session.connectGoogle() }
            } label: {
                HStack {
                    if session.isWorking { ProgressView().controlSize(.small) }
                    Text(session.isWorking ? "Verbindung wird hergestellt …" : "Mit Google / YouTube anmelden")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isWorking)

            if !session.channels.isEmpty {
                Text("Deinen Kanal auswählen").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(session.channels) { channel in
                            Button {
                                Task { await session.useConnectedChannel(channel.id) }
                            } label: {
                                HStack {
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
            DisclosureGroup("Erweiterte App-Einstellungen") {
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
        .padding(24)
        .frame(width: 560)
        .fileImporter(isPresented: $showConfigurationImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result, session.importOAuthJSON(from: url) {
                session.connectionStatusMessage = "Google-Anmeldung ist vorbereitet. Du kannst dich jetzt anmelden."
            }
        }
    }
}
#endif
