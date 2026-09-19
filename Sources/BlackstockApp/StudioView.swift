#if os(macOS)
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import BlackstockCore

struct StudioView: View {
    let project: BlackstockProject
    let opportunitySource: MediaSourceReference?
    let contentLanguage: String

    @StateObject private var state = StudioState()
    @State private var showImporter = false
    @State private var pendingURL: URL?
    @State private var showRightsSheet = false
    @State private var rightsSelection: ProductionMediaAuthorization = .owned
    @State private var rightsEvidence = ""
    @State private var rightsConfirmed = false
    @State private var showPackagingReview = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let opportunitySource {
                sourceContext(opportunitySource)
                Divider()
            }

            if let asset = state.asset {
                editor(asset)
            } else {
                emptyState
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingURL = url
                rightsEvidence = ""
                rightsConfirmed = false
                rightsSelection = .owned
                showRightsSheet = true
            }
        }
        .sheet(isPresented: $showRightsSheet) {
            rightsSheet
        }
        .sheet(isPresented: $showPackagingReview) {
            if let asset = state.asset,
               let artifact = state.renderArtifact {
                PackagingReviewView(
                    project: project,
                    asset: asset,
                    artifact: artifact,
                    transcript: state.transcript,
                    generatedCaptionURL: state.captionURL
                )
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Studio")
                    .font(.title2.bold())
                Text("Vorschau und non-destruktive Bearbeitung")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(project.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("Zielkanal: \(project.targetChannelID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("Video importieren …") {
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
    }

    private func sourceContext(_ source: MediaSourceReference) -> some View {
        let resolution = MediaSourceResolver().resolve(
            source,
            approvedProvider: nil
        )

        return HStack(spacing: 12) {
            Image(systemName: source.provider == .youtube ? "play.rectangle" : "link")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Opportunity-Quelle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(source.pageURL.absoluteString)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(resolution.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if source.provider == .youtube, let videoID = source.externalID {
                YouTubeEmbeddedPlayer(videoID: videoID)
                    .frame(width: 220, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.018))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Autorisiertes Produktionsvideo hinzufügen")
                .font(.title2.bold())
            Text("Blackstock übernimmt nur Medien in die Bearbeitung, deren Nutzung nachvollziehbar autorisiert ist.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            Button("Video auswählen …") {
                showImporter = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editor(_ asset: ProductionMediaAsset) -> some View {
        HSplitView {
            VStack(spacing: 12) {
                VideoPlayer(player: state.player)
                    .frame(minWidth: 620, minHeight: 360)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                timeline(asset)
                    .frame(height: 112)

                HStack {
                    Button {
                        Task { await state.undo() }
                    } label: {
                        Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(state.graph.head.parentID == nil)

                    Button {
                        Task { await state.redo() }
                    } label: {
                        Label("Wiederholen", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(state.lastUndoneRevisionID == nil)

                    Spacer()

                    Text("\(state.graph.currentOperations.count) Änderungen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let artifact = state.renderArtifact {
                    HStack {
                        Label("Render bereit", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text(String(artifact.sha256.prefix(12)) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button("Packaging & Review") {
                            showPackagingReview = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }

                if let error = state.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(minWidth: 700)

            inspector(asset)
                .frame(minWidth: 300, idealWidth: 330, maxWidth: 380)
        }
    }

    private func timeline(_ asset: ProductionMediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                Spacer()
                Text(timeLabel(state.trimStart) + " – " + timeLabel(state.trimEnd))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 28)

                HStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { state.trimStart },
                            set: { state.trimStart = min($0, state.trimEnd) }
                        ),
                        in: 0...max(asset.durationSeconds, 0.01)
                    )
                    Slider(
                        value: Binding(
                            get: { state.trimEnd },
                            set: { state.trimEnd = max($0, state.trimStart) }
                        ),
                        in: 0...max(asset.durationSeconds, 0.01)
                    )
                }
                .padding(.horizontal, 10)
            }

            HStack {
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Trim anwenden") {
                    Task { await state.applyTrim() }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text("Ende")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }

    private func inspector(_ asset: ProductionMediaAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(asset.displayName)
                        .font(.headline)
                    Text("Dauer: \(timeLabel(asset.durationSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktueller Schritt")
                        .font(.headline)
                    Label("Ausschnitt festlegen", systemImage: "scissors")
                    Text("Weitere Werkzeuge erscheinen erst, wenn ihre Capability real implementiert und getestet ist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Render")
                        .font(.headline)

                    Picker("Qualität", selection: $state.renderPreset) {
                        Text("1080p").tag(LocalRenderPreset.hd1080)
                        Text("4K").tag(LocalRenderPreset.uhd4K)
                    }
                    .pickerStyle(.segmented)

                    Button {
                        Task { await state.render(projectID: project.id) }
                    } label: {
                        HStack {
                            if state.isRendering {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                state.isRendering ? "Render läuft …" : "Lokalen Render erstellen",
                                systemImage: "film"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isRendering)

                    Text("Blackstock rendert lokal auf dem Mac. Erst ein validiertes Render-Artefakt darf in Packaging/Publishing weitergehen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Technische Audioprüfung")
                        .font(.headline)

                    if let assessment = state.audioTechnicalAssessment {
                        if !assessment.snapshot.hasAudioTrack {
                            Label("Keine Audiospur erkannt", systemImage: "speaker.slash")
                                .foregroundStyle(.red)
                        } else {
                            if let sampleRate = assessment.snapshot.sampleRateHz {
                                Label(
                                    "Sample-Rate: \(Int(sampleRate.rounded())) Hz",
                                    systemImage: "waveform"
                                )
                            }
                            if let channels = assessment.snapshot.channelCount {
                                Label(
                                    "Kanäle: \(channels)",
                                    systemImage: "speaker.wave.2"
                                )
                            }

                            if assessment.findings.isEmpty {
                                Text("Keine Auffälligkeit in der technischen Basisprüfung.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(assessment.findings, id: \.self) { finding in
                                    Label(audioFindingText(finding), systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                }
                            }
                        }

                        Text("Diese Prüfung bewertet nur Audiospur, Sample-Rate und Kanalzahl. Loudness, Clipping und Sprachverständlichkeit bleiben separate Gates.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Noch keine technische Audioprüfung verfügbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Captions")
                        .font(.headline)

                    Button {
                        Task {
                            await state.generateLocalCaptions(
                                localeIdentifier: speechLocaleIdentifier
                            )
                        }
                    } label: {
                        HStack {
                            if state.isTranscribing {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                state.isTranscribing
                                    ? "Transkription läuft …"
                                    : "On-Device-Captions erstellen",
                                systemImage: "captions.bubble"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isTranscribing)

                    Text("Sprache: \(speechLocaleIdentifier) · nur On-Device; kein stiller Cloud-Fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let transcript = state.transcript {
                        DisclosureGroup("Transkript anzeigen") {
                            Text(transcript.text)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding(.top, 6)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Verlauf")
                        .font(.headline)

                    ForEach(Array(state.ledger.events.reversed())) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.summary)
                                .font(.caption.weight(.semibold))
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(18)
        }
        .background(Color.primary.opacity(0.02))
    }

    private var rightsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Produktionsmedium autorisieren")
                .font(.title2.bold())

            Text(pendingURL?.lastPathComponent ?? "Video")
                .foregroundStyle(.secondary)

            Picker("Nutzungsgrundlage", selection: $rightsSelection) {
                Text("Eigenes Material").tag(ProductionMediaAuthorization.owned)
                Text("Lizenziert").tag(ProductionMediaAuthorization.licensed)
                Text("Explizit autorisiert").tag(ProductionMediaAuthorization.explicitlyAuthorized)
            }

            TextField("Nachweis / Referenz, z. B. „eigene Aufnahme 18.09.2026“", text: $rightsEvidence)
                .textFieldStyle(.roundedBorder)

            Toggle(isOn: $rightsConfirmed) {
                Text("Ich bestätige, dass ich Eigentümer bin oder die nötigen Nutzungs-, Bearbeitungs- und Veröffentlichungsrechte besitze und für diese Angabe verantwortlich bin.")
                    .font(.callout)
            }

            Text("Blackstock speichert Bestätigung und Nachweis als Produktions-Provenance. Diese Bestätigung ersetzt keine Plattformregeln und keine tatsächlich erforderliche Lizenz.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Abbrechen", role: .cancel) {
                    showRightsSheet = false
                    pendingURL = nil
                }
                Spacer()
                Button("Importieren") {
                    guard let url = pendingURL else { return }
                    showRightsSheet = false
                    Task {
                        await state.importMovie(
                            url: url,
                            authorization: rightsSelection,
                            rightsEvidence: rightsEvidence,
                            rightsConfirmed: rightsConfirmed
                        )
                    }
                    pendingURL = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    rightsEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !rightsConfirmed
                )
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func audioFindingText(
        _ finding: AudioTechnicalFinding
    ) -> String {
        switch finding {
        case .noAudioTrack:
            return "Keine Audiospur vorhanden."
        case .lowSampleRate:
            return "Die Sample-Rate liegt unter 44,1 kHz."
        case .monoAudio:
            return "Das Material ist mono. Das ist nicht automatisch falsch, sollte aber bewusst geprüft werden."
        }
    }

    private var speechLocaleIdentifier: String {
        switch contentLanguage {
        case "de": return "de-DE"
        case "en": return "en-US"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "it": return "it-IT"
        case "pt": return "pt-PT"
        default: return contentLanguage
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
#endif
