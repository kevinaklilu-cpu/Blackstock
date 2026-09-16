#if os(macOS)
import SwiftUI
struct SettingsView: View {
    @Binding var apiKey: String
    @State private var draft = ""
    var body: some View { Form { Section("Live-Daten") { SecureField("YouTube Data API Key", text: $draft); Text("Wird im macOS-Schlüsselbund gespeichert. Dieser Schlüssel reicht für öffentliche Trend- und Videodaten; der OAuth-Uploadfluss ist davon getrennt.").font(.caption).foregroundStyle(.secondary); HStack { Button("Speichern") { Keychain.write(draft, account: "youtube-data-api-key"); apiKey = draft }; Button("Entfernen") { draft = ""; Keychain.write("", account: "youtube-data-api-key"); apiKey = "" } } }; Section("Produktprinzip") { Text("Blackstock zeigt keine künstlichen Chance-/Virality-Zahlen. Empfehlungen müssen durch konkrete Signale erklärbar sein.") } }.formStyle(.grouped).navigationTitle("Einstellungen").onAppear { draft = apiKey } }
}
#endif
