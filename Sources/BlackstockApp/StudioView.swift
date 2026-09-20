#if os(macOS)
import SwiftUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers
import BlackstockCore

struct StudioView: View {
    @ObservedObject var session: BlackstockSession
    let project: BlackstockProject
    let opportunitySource: MediaSourceReference?
    let contentLanguage: String

    @StateObject private var state = StudioState()
    @State private var showImporter = false
    @State private var pendingURL: URL?
    @State private var pendingCaptureKind: CaptureKind?
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
                pendingCaptureKind = nil
                rightsEvidence = ""
                rightsConfirmed = false
                rightsSelection = .owned
                showRightsSheet = true
            }
        }
        .sheet(isPresented: $showRightsSheet) {
            rightsSheet
        }
        .task(id: project.id) {
            await state.loadWorkspace(projectID: project.id)
        }
        .sheet(isPresented: $showPackagingReview) {
            if let asset = state.asset,
               let artifact = state.renderArtifact {
                PackagingReviewView(
                    session: session,
                    project: project,
                    asset: asset,
                    artifact: artifact,
                    transcript: state.transcript,
                    generatedCaptionURL: state.captionURL,
                    audioTechnicalAssessment: state.audioTechnicalAssessment,
                    audioSignalAssessment: state.audioSignalAssessment,
                    audioLoudnessAssessment: state.audioLoudnessAssessment,
                    storyboard: state.storyboard
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
                Text("Status: \(currentStage.rawValue)")
                    .font(.caption2.monospaced())
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
                .font(.largeTitle)
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

            CaptureCapabilityPanel { url, kind in
                pendingURL = url
                pendingCaptureKind = kind
                rightsSelection = .owned
                rightsEvidence = "Direkt mit Blackstock aufgezeichnet: \(kind.germanTitle)"
                rightsConfirmed = false
                showRightsSheet = true
            }
            .frame(maxWidth: 620)

            if !state.supplementalCaptures.isEmpty {
                supplementalCapturesSection
                    .frame(maxWidth: 620)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editor(_ asset: ProductionMediaAsset) -> some View {
        HSplitView {
            VStack(spacing: 12) {
                ZStack(alignment: .bottom) {
                    VideoPlayer(player: state.player)
                        .accessibilityLabel(
                            "Video-Vorschau des aktuellen Schnitts"
                        )

                    if state.burnInCaptionsEnabled,
                       state.previewedLocalClipCandidateID == nil {
                        captionPreviewOverlay
                    }
                }
                .frame(minWidth: 620, minHeight: 360)
                .background(.black)
                .clipShape(
                    RoundedRectangle(cornerRadius: 12)
                )

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
                        Button("Veröffentlichungspaket & Prüfung") {
                            if currentStage == .editing {
                                if session.advanceActiveProject(
                                    to: .packaging
                                ) {
                                    showPackagingReview = true
                                }
                            } else if currentStage == .packaging
                                        || currentStage == .review {
                                showPackagingReview = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            currentStage != .editing
                            && currentStage != .packaging
                            && currentStage != .review
                        )
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

    private var localClipCandidatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lokale Clip-Kandidaten")
                .font(.headline)

            Text("Blackstock analysiert das autorisierte Originalmedium lokal auf Sprachsegmente und gemessene Pausen. Die Vorschläge enthalten keine Erfolgs-, Qualitäts- oder Viralitätsnote und verändern den Schnitt erst nach deiner Auswahl.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await state.generateLocalClipCandidates(
                        localeIdentifier:
                            speechLocaleIdentifier
                    )
                }
            } label: {
                HStack {
                    if state.isGeneratingClipCandidates {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        state.isGeneratingClipCandidates
                            ? "Lokale Clip-Analyse läuft …"
                            : "Clip-Kandidaten lokal finden",
                        systemImage: "scissors.badge.ellipsis"
                    )
                }
            }
            .buttonStyle(.bordered)
            .disabled(
                state.isGeneratingClipCandidates
                || !editingEnabled
            )

            if let message =
                state.clipCandidateStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                Array(
                    state.localClipCandidates
                        .enumerated()
                ),
                id: \.element.id
            ) { index, candidate in
                GroupBox(
                    "Kandidat \(index + 1)"
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        HStack(spacing: 12) {
                            Label(
                                timeLabel(
                                    candidate.sourceRange
                                        .startSeconds
                                )
                                + " – "
                                + timeLabel(
                                    candidate.sourceRange
                                        .endSeconds
                                ),
                                systemImage: "clock"
                            )
                            Label(
                                timeLabel(
                                    candidate.sourceRange
                                        .durationSeconds
                                ),
                                systemImage:
                                    "timer"
                            )
                            Label(
                                "\(candidate.wordCount) Wörter",
                                systemImage:
                                    "text.word.spacing"
                            )
                        }
                        .font(
                            .caption.monospacedDigit()
                        )
                        .foregroundStyle(.secondary)

                        if let confidence =
                            candidate.averageConfidence {
                            Text(
                                "Mittlere Spracherkennungs-Konfidenz: "
                                + String(
                                    format: "%.0f%%",
                                    Double(confidence)
                                        * 100
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Text(
                            candidate.transcriptPreview
                        )
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )

                        HStack {
                            Button {
                                Task {
                                    await state
                                        .previewLocalClipCandidate(
                                            candidate
                                        )
                                }
                            } label: {
                                Label(
                                    state.previewedLocalClipCandidateID
                                        == candidate.id
                                        ? "Vorschau läuft"
                                        : "Vorschau abspielen",
                                    systemImage:
                                        "play.circle"
                                )
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task {
                                    await state
                                        .applyLocalClipCandidate(
                                            candidate
                                        )
                                }
                            } label: {
                                Label(
                                    "Diesen Ausschnitt übernehmen",
                                    systemImage:
                                        "checkmark.circle"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!editingEnabled)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if state.previewedLocalClipCandidateID != nil {
                Button {
                    Task {
                        await state.restoreEditedPreview()
                    }
                } label: {
                    Label(
                        "Zurück zur aktuellen Schnittvorschau",
                        systemImage: "arrow.uturn.backward.circle"
                    )
                }
                .buttonStyle(.bordered)
            }

            if !state.localClipCandidates.isEmpty {
                Text("Eine Kandidaten-Vorschau verändert den EditGraph nicht. Erst „Diesen Ausschnitt übernehmen“ speichert eine non-destruktive Trim-Revision, die über Rückgängig wieder verlassen werden kann.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
                    .accessibilityLabel("Trim-Start")
                    .accessibilityValue(timeLabel(state.trimStart))
                    .disabled(!editingEnabled)
                    Slider(
                        value: Binding(
                            get: { state.trimEnd },
                            set: { state.trimEnd = max($0, state.trimStart) }
                        ),
                        in: 0...max(asset.durationSeconds, 0.01)
                    )
                    .accessibilityLabel("Trim-Ende")
                    .accessibilityValue(timeLabel(state.trimEnd))
                    .disabled(!editingEnabled)
                }
                .padding(.horizontal, 10)
            }

            HStack {
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Als Trim setzen") {
                    Task { await state.applyTrim() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!editingEnabled)

                Button("Auswahl entfernen") {
                    Task { await state.applyRemoveRange() }
                }
                .buttonStyle(.bordered)
                .disabled(!editingEnabled)
                Spacer()
                Text("Ende")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Trim und Entfernen bleiben non-destruktiv im EditGraph und können rückgängig gemacht werden.")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                    Label(stageTitle(currentStage), systemImage: stageIcon(currentStage))
                    Text(stageExplanation(currentStage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !state.supplementalCaptures.isEmpty {
                    Divider()
                    supplementalCapturesSection
                }

                Divider()

                storyboardSection

                Divider()

                localClipCandidatesSection

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Bildformat & Fokus")
                        .font(.headline)

                    Picker("Format", selection: $state.reframeAspectRatio) {
                        ForEach(ReframeAspectRatio.allCases, id: \.self) { ratio in
                            Text(ratio.germanTitle).tag(ratio)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Fokus horizontal")
                            Spacer()
                            Text(String(format: "%.0f%%", state.reframeFocalX * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $state.reframeFocalX, in: 0...1)
                            .accessibilityLabel("Fokus horizontal")
                            .accessibilityValue(
                                String(format: "%.0f Prozent", state.reframeFocalX * 100)
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Fokus vertikal")
                            Spacer()
                            Text(String(format: "%.0f%%", state.reframeFocalY * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $state.reframeFocalY, in: 0...1)
                            .accessibilityLabel("Fokus vertikal")
                            .accessibilityValue(
                                String(format: "%.0f Prozent", state.reframeFocalY * 100)
                            )
                    }

                    HStack {
                        Button {
                            Task { await state.suggestFocalPoint() }
                        } label: {
                            HStack {
                                if state.isSuggestingFocalPoint {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    state.isSuggestingFocalPoint
                                        ? "Vision analysiert …"
                                        : "Fokus vorschlagen",
                                    systemImage: "viewfinder"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isSuggestingFocalPoint)

                        Button("Ausschnitt anwenden") {
                            Task { await state.applyReframe() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!editingEnabled)
                    }

                    if let proposal = state.focalPointProposal {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(proposal.explanation)
                                .font(.caption.weight(.semibold))
                            Text("\(proposal.observationCount) relevante Beobachtungen aus \(proposal.sampledFrameCount) Stichproben. Noch nicht angewendet.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Vision darf nur die Regler vorpositionieren. Erst „Ausschnitt anwenden“ schreibt eine Änderung in den EditGraph; Vorschau und finales Rendering verwenden danach dieselbe Ausschnitt-Geometrie.")
                        .font(.caption2)
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
                    .disabled(state.isRendering || !editingEnabled)

                    Text("Blackstock rendert lokal auf dem Mac. Erst ein validiertes Render-Artefakt darf in Veröffentlichungspaket und Veröffentlichung weitergehen.")
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

                        if let signal = state.audioSignalAssessment {
                            Divider()

                            HStack(spacing: 10) {
                                if let peak = signal.snapshot.peakDBFS {
                                    metricPill("Peak", String(format: "%.1f dBFS", peak))
                                }
                                if let rms = signal.snapshot.rmsDBFS {
                                    metricPill("RMS", String(format: "%.1f dBFS", rms))
                                }
                            }

                            if signal.snapshot.fullScaleSampleCount > 0 {
                                Label(
                                    "\(signal.snapshot.fullScaleSampleCount) Full-Scale-Samples erkannt",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            } else if signal.snapshot.analyzedSampleCount > 0 {
                                Label(
                                    "Keine Full-Scale-Samples in \(signal.snapshot.analyzedSampleCount) analysierten Samples erkannt.",
                                    systemImage: "checkmark.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Text("Peak/RMS sind Messwerte, keine LUFS-Messung und keine Qualitätsnote. Sprachverständlichkeit bleibt eine eigene Hörprüfung.")
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
                    Text("Untertitel")
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
                                    : "Lokale Untertitel erstellen",
                                systemImage: "captions.bubble"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isTranscribing || !editingEnabled)

                    Text("Sprache: \(speechLocaleIdentifier) · nur lokal auf dem Gerät; kein stiller Cloud-Fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let transcript = state.transcript {
                        Toggle(
                            isOn: Binding(
                                get: {
                                    state.burnInCaptionsEnabled
                                },
                                set: {
                                    state.setBurnInCaptionsEnabled(
                                        $0
                                    )
                                }
                            )
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 2
                            ) {
                                Text(
                                    "Sichtbare Captions ins Video rendern"
                                )
                                    .font(
                                        .caption.weight(
                                            .semibold
                                        )
                                    )
                                Text(
                                    "Zusätzlich zur VTT-Datei lokal in die MP4 einbrennen."
                                )
                                    .font(.caption2)
                                    .foregroundStyle(
                                        .secondary
                                    )
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!editingEnabled)

                        DisclosureGroup("Transkript anzeigen") {
                            Text(transcript.text)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding(.top, 6)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                if let structure = state.transcriptStructure {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Zuschauerbindung & Struktur")
                            .font(.headline)

                        ForEach(structure.factualSummary, id: \.self) { fact in
                            Label(fact, systemImage: "ruler")
                                .font(.caption)
                        }

                        Button {
                            Task { await state.analyzeRetentionLocally() }
                        } label: {
                            HStack {
                                if state.isAnalyzingRetention {
                                    ProgressView().controlSize(.small)
                                }
                                Label(
                                    state.isAnalyzingRetention
                                        ? "Lokales Modell analysiert …"
                                        : "Lokale Hinweise erstellen",
                                    systemImage: "sparkles"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            state.isAnalyzingRetention
                            || state.retentionAdvisorAvailability != .available
                        )

                        if let availability = state.retentionAdvisorAvailability,
                           availability != .available {
                            Text(retentionAvailabilityText(availability))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let advisory = state.retentionAdvisory {
                            DisclosureGroup("Hinweise anzeigen") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(advisory.text)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                    Text("Quelle: \(advisory.source) · keine Release-Evidenz")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                            }
                            .font(.caption.weight(.semibold))
                        }

                        Text("Blackstock misst die Struktur-Fakten deterministisch. Generative Hinweise sind optional, lokal und ersetzen keine Sichtprüfung oder echte Analytics.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var captionPreviewOverlay: some View {
        if let transcript = state.transcript {
            TimelineView(
                .periodic(
                    from: .now,
                    by: 0.10
                )
            ) { _ in
                if let text = activeCaptionText(
                    transcript: transcript,
                    timeSeconds: max(
                        CMTimeGetSeconds(
                            state.player.currentTime()
                        ),
                        0
                    )
                ) {
                    Text(text)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 560)
                        .background(
                            Color.black.opacity(0.72),
                            in: RoundedRectangle(
                                cornerRadius: 12
                            )
                        )
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                        .accessibilityLabel(
                            "Burn-in-Caption: \(text)"
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func activeCaptionText(
        transcript: LocalTranscript,
        timeSeconds: Double
    ) -> String? {
        transcript.segments.first {
            let start = max(
                $0.startSeconds,
                0
            )
            let end =
                start
                + max(
                    $0.durationSeconds,
                    0.05
                )
            return timeSeconds >= start
                && timeSeconds < end
        }?
        .text
        .trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .flatMap {
            $0.isEmpty ? nil : $0
        }
    }

    private var rightsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Produktionsmedium autorisieren")
                .font(.title2.bold())

            Text(pendingURL?.lastPathComponent ?? "Produktionsmedium")
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
                    if pendingCaptureKind != nil,
                       let pendingURL {
                        try? FileManager.default.removeItem(
                            at: pendingURL
                        )
                    }
                    pendingURL = nil
                    pendingCaptureKind = nil
                }
                Spacer()
                Button(
                    pendingCaptureKind == .microphone
                        ? "Im Projekt speichern"
                        : "Importieren"
                ) {
                    guard let url = pendingURL else { return }
                    let captureKind = pendingCaptureKind
                    showRightsSheet = false

                    Task {
                        if captureKind == .microphone {
                            let saved = await state.importSupplementalCapture(
                                url: url,
                                kind: .microphone,
                                projectID: project.id,
                                rightsBasis: rightsBasisLabel(
                                    rightsSelection
                                ),
                                rightsEvidence: rightsEvidence,
                                rightsConfirmed: rightsConfirmed
                            )
                            if saved,
                               let persisted = state
                                    .supplementalCaptures
                                    .last(where: {
                                        $0.kind == .microphone
                                    }) {
                                await BlackstockCaptureHardwareAudit
                                    .recordPersistedCapture(
                                        kind: .microphone,
                                        fileURL:
                                            persisted.fileURL,
                                        projectID: project.id
                                    )
                                try? FileManager.default.removeItem(
                                    at: url
                                )
                                BlackstockCaptureHardwareAudit
                                    .recordTemporaryCleanup(
                                        for: .microphone,
                                        temporaryURL: url
                                    )
                            }
                        } else {
                            let previousAssetID = state.asset?.id
                            await state.importMovie(
                                url: url,
                                projectID: project.id,
                                authorization: rightsSelection,
                                rightsEvidence: rightsEvidence,
                                rightsConfirmed: rightsConfirmed
                            )
                            if let imported = state.asset,
                               imported.id != previousAssetID {
                                if let captureKind {
                                    await BlackstockCaptureHardwareAudit
                                        .recordPersistedCapture(
                                            kind: captureKind,
                                            fileURL:
                                                imported.sourceURL,
                                            projectID: project.id
                                        )
                                    try? FileManager.default.removeItem(
                                        at: url
                                    )
                                    BlackstockCaptureHardwareAudit
                                        .recordTemporaryCleanup(
                                            for: captureKind,
                                            temporaryURL: url
                                        )
                                }
                                if currentStage == .production {
                                    _ = session.advanceActiveProject(
                                        to: .preview
                                    )
                                }
                            }
                        }

                        pendingURL = nil
                        pendingCaptureKind = nil
                    }
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

    @ViewBuilder
    private var supplementalCapturesSection: some View {
        GroupBox("Zusätzliche Aufnahmen") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.supplementalCaptures) { capture in
                    HStack(spacing: 8) {
                        Image(
                            systemName: capture.kind == .microphone
                                ? "mic.fill"
                                : "waveform"
                        )
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(capture.kind.germanTitle)
                                .font(.caption.weight(.semibold))
                            Text(capture.fileURL.lastPathComponent)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(capture.rightsEvidence)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Label(
                            "Rechte bestätigt",
                            systemImage: "checkmark.shield"
                        )
                        .font(.caption2)
                    }
                }

                Text("Zusätzliche Audioaufnahmen bleiben getrennt vom Hauptvideo und können später gezielt in den Audiomix übernommen werden.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func rightsBasisLabel(
        _ authorization: ProductionMediaAuthorization
    ) -> String {
        switch authorization {
        case .owned:
            return "Eigenes Material"
        case .licensed:
            return "Lizenziert"
        case .explicitlyAuthorized:
            return "Explizit autorisiert"
        case .unknown:
            return "Unbekannt"
        case .prohibited:
            return "Nicht zulässig"
        }
    }

    private func metricPill(
        _ title: String,
        _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    @ViewBuilder
    private var storyboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Storyboard")
                    .font(.headline)
                Spacer()
                if let plan = state.storyboard {
                    Text("v\(plan.version)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if currentStage == .preview {
                Text("Die Vorschau ist verfügbar. Starte jetzt das Storyboard, bevor Schnittwerkzeuge freigeschaltet werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Storyboard starten") {
                    if session.advanceActiveProject(to: .storyboard) {
                        state.loadStoryboard(projectID: project.id)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if currentStage == .storyboard
                        || currentStage == .editing
                        || currentStage == .packaging
                        || currentStage == .review
                        || currentStage == .publishing
                        || currentStage == .published {
                if let plan = state.storyboard {
                    if plan.beats.isEmpty {
                        Text("Noch keine Beats. Lege mindestens einen klaren Abschnitt an.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(
                        Array(plan.beats.enumerated()),
                        id: \.element.id
                    ) { index, beat in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                TextField(
                                    "Beat-Titel",
                                    text: Binding(
                                        get: {
                                            state.storyboard?.beats
                                                .first(where: { $0.id == beat.id })?
                                                .title ?? beat.title
                                        },
                                        set: {
                                            state.updateStoryboardBeat(
                                                id: beat.id,
                                                title: $0
                                            )
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                            }

                            TextField(
                                "Zweck dieses Beats",
                                text: Binding(
                                    get: {
                                        state.storyboard?.beats
                                            .first(where: { $0.id == beat.id })?
                                            .purpose ?? beat.purpose
                                    },
                                    set: {
                                        state.updateStoryboardBeat(
                                            id: beat.id,
                                            purpose: $0
                                        )
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            TextField(
                                "Visuelle Richtung / Shot / B-Roll",
                                text: Binding(
                                    get: {
                                        state.storyboard?.beats
                                            .first(where: { $0.id == beat.id })?
                                            .visualDirection
                                            ?? beat.visualDirection
                                    },
                                    set: {
                                        state.updateStoryboardBeat(
                                            id: beat.id,
                                            visualDirection: $0
                                        )
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            if currentStage == .storyboard {
                                HStack {
                                    Button {
                                        state.moveStoryboardBeat(
                                            from: index,
                                            to: max(index - 1, 0)
                                        )
                                    } label: {
                                        Image(systemName: "arrow.up")
                                    }
                                    .accessibilityLabel("Beat nach oben verschieben")
                                    .disabled(index == 0)

                                    Button {
                                        state.moveStoryboardBeat(
                                            from: index,
                                            to: min(
                                                index + 2,
                                                plan.beats.count
                                            )
                                        )
                                    } label: {
                                        Image(systemName: "arrow.down")
                                    }
                                    .accessibilityLabel("Beat nach unten verschieben")
                                    .disabled(index == plan.beats.count - 1)

                                    Spacer()

                                    Button(role: .destructive) {
                                        state.removeStoryboardBeat(
                                            id: beat.id
                                        )
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .accessibilityLabel("Beat löschen")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(8)
                        .background(
                            Color.primary.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    }

                    if currentStage == .storyboard {
                        Button("Beat hinzufügen") {
                            state.addStoryboardBeat(
                                projectID: project.id
                            )
                        }
                        .buttonStyle(.bordered)

                        Button("Bearbeitung starten") {
                            _ = session.advanceActiveProject(
                                to: .editing
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!plan.isReadyForEditing)
                    }
                }
            } else {
                Text("Lade zuerst ein autorisiertes Produktionsmedium, um die Vorschau zu erzeugen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var currentStage: BlackstockStage {
        session.activeProject?.stage ?? project.stage
    }

    private var editingEnabled: Bool {
        currentStage == .editing
    }

    private func stageTitle(_ stage: BlackstockStage) -> String {
        switch stage {
        case .production: return "Produktionsmedium vorbereiten"
        case .preview: return "Vorschau prüfen"
        case .storyboard: return "Storyboard strukturieren"
        case .editing: return "Video bearbeiten"
        case .packaging: return "Veröffentlichungspaket vorbereiten"
        case .review: return "Release prüfen"
        case .publishing: return "Veröffentlichung läuft"
        case .published: return "Veröffentlicht"
        case .discovery: return "Discovery"
        case .research: return "Research"
        case .analysis: return "Analyse"
        }
    }

    private func stageIcon(_ stage: BlackstockStage) -> String {
        switch stage {
        case .production: return "square.and.arrow.down"
        case .preview: return "play.rectangle"
        case .storyboard: return "rectangle.3.group"
        case .editing: return "scissors"
        case .packaging: return "shippingbox"
        case .review: return "checklist"
        case .publishing: return "arrow.up.circle"
        case .published: return "checkmark.seal"
        case .discovery: return "sparkle.magnifyingglass"
        case .research: return "books.vertical"
        case .analysis: return "chart.xyaxis.line"
        }
    }

    private func stageExplanation(_ stage: BlackstockStage) -> String {
        switch stage {
        case .production:
            return "Importiere autorisiertes Material. Bearbeitung bleibt bis zur Vorschau und zum Storyboard gesperrt."
        case .preview:
            return "Prüfe das geladene Medium und starte anschließend das Storyboard."
        case .storyboard:
            return "Lege die Beats und ihre Funktion fest. Danach wird die Bearbeitung freigeschaltet."
        case .editing:
            return "Schnitt, Neuausrichtung, Untertitel, Audio-Prüfung und Rendering sind jetzt verfügbar."
        case .packaging:
            return "Bearbeitung ist eingefroren; Metadaten, Vorschaubild, Untertitel und Prüfung folgen."
        case .review:
            return "Alle Freigabeprüfungen müssen belegt sein, bevor die Veröffentlichung starten darf."
        case .publishing:
            return "Externe Aktionen werden protokolliert und auf den Zielkanal begrenzt."
        case .published:
            return "Die YouTube-Video-ID ist gespeichert; Analytics kann zurückgeführt werden."
        case .discovery, .research, .analysis:
            return "Dieser Projektstatus liegt vor der Produktionsphase."
        }
    }

    private func retentionAvailabilityText(
        _ availability: LocalRetentionAdvisorAvailability
    ) -> String {
        switch availability {
        case .available:
            return "Lokale Hinweise zur Zuschauerbindung sind verfügbar."
        case .unsupportedOS:
            return "Lokale Foundation-Models-Hinweise benötigen eine unterstützte macOS-Version."
        case .frameworkUnavailable:
            return "Foundation Models sind in dieser Laufzeit nicht verfügbar."
        case .modelUnavailable:
            return "Das lokale Apple-Intelligence-Modell ist auf diesem Mac derzeit nicht verfügbar."
        case .unsupportedLanguage:
            return "Das lokale Modell unterstützt die Content-Sprache derzeit nicht."
        }
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
