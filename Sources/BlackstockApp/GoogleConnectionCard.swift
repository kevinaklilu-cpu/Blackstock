#if os(macOS)
import SwiftUI

/// Shared ordering for first launch and reconnect: local configuration, then OAuth.
struct GoogleConnectionCard: View {
    let isReady: Bool
    let isWorking: Bool
    let importConfiguration: () -> Void
    let signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: isReady ? "checkmark.shield.fill" : "doc.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(isReady ? Color.green : Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(isReady ? "Verbindung vorbereitet" : "Desktop-OAuth-Datei hinzufügen")
                        .font(.headline)
                    Text(isReady ? "Deine JSON ist geprüft und bereit." : "Beginne mit deiner Google-Konfiguration (.json).")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if isReady {
                Button("Andere JSON auswählen …", action: importConfiguration)
                    .buttonStyle(.link)
                    .disabled(isWorking)
                Divider()
                Text("Verbinde jetzt dein Google-Konto. Deinen YouTube-Kanal wählst du danach selbst aus.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: signIn) {
                    HStack(spacing: 10) {
                        if isWorking { ProgressView().controlSize(.small) }
                        else { Image(systemName: "person.crop.circle") }
                        Text(isWorking ? "Auf Google-Anmeldung warten …" : "Mit Google / YouTube anmelden")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking || !isReady)
            } else {
                Button(action: importConfiguration) {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Desktop-OAuth-JSON auswählen …")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                Label("Danach: bei Google anmelden und Kanal auswählen", systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Label("Die JSON wird lokal importiert. Dein Google-Passwort gibst du nur bei Google ein.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.08)))
        .animation(.easeInOut(duration: 0.2), value: isReady)
    }
}
#endif
