#if os(macOS)
import AppKit
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
    @StateObject private var sourceDownloader =
        SourceDownloadManager()
    @StateObject private var ingestWatcher =
        IngestDirectoryWatcher()
    @State private var pendingURL: URL?
    @State private var showOptionalCapture = false
    @State private var isResolvingAutomaticSource = false
    @State private var showSourceDownloader = false
    @State private var sourceDownloadURLText = ""
    @State private var sourceDownloadMessage: String?
    @State private var pendingCaptureKind: CaptureKind?
    @State private var showRightsSheet = false
    @State private var rightsSelection: ProductionMediaAuthorization = .owned
    @State private var rightsEvidence = ""
    @State private var rightsConfirmed = false
    @State private var showPackagingReview = false
    @State private var showClipExportFolderImporter = false
    @State private var activeProcessingTask: Task<Void, Never>?
    @State private var selectedCaptionSegmentID: UUID?
    @State private var captionEditText = ""
    @State private var captionEditStartSeconds: Double = 0
    @State private var captionEditDurationSeconds: Double = 1

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
        .background(BlackstockDesign.canvas)
        .fileImporter(
            isPresented: $showClipExportFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result,
               let directoryURL = urls.first {
                state.exportRenderedSavedClips(
                    to: directoryURL
                )
            }
        }
        .sheet(isPresented: $showRightsSheet) {
            rightsSheet
        }
        .task(id: project.id) {
            await state.loadWorkspace(
                projectID: project.id
            )
            if session.activeProject?.isPaused == true {
                state.requestStopProcessing()
                return
            }

            guard state.asset == nil,
                  session.productionIntent(
                    for: project.id
                  )?.isLinkFirstClip == true,
                  session.workspaceRightsAttestation?
                    .permitsUserDirectedProduction == true else {
                return
            }

            startIngestWatcher()
            await attemptAutomaticOriginalBinding()
        }
        .onDisappear {
            activeProcessingTask?.cancel()
            activeProcessingTask = nil
            ingestWatcher.stop()
        }
        .onChange(of: session.activeProject?.isPaused) { paused in
            if paused == true {
                activeProcessingTask?.cancel()
                activeProcessingTask = nil
                state.requestStopProcessing()
            } else {
                state.resumeProcessing()
            }
        }
        .sheet(isPresented: $showSourceDownloader) {
            sourceDownloaderSheet
        }
        .onChange(
            of: sourceDownloader.lastCompletedURL
        ) { completedURL in
            guard let completedURL else {
                return
            }
            pendingURL = completedURL
            pendingCaptureKind = nil
            importPendingMedia()
            showSourceDownloader = false
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
                    storyboard: state.storyboard,
                    suggestedTitle:
                        state.packagingSuggestedTitle
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.title)
                    .font(.title2.bold())
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label("Editor", systemImage: "scissors")
                    Text("•")
                    Text(currentStage.rawValue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            if session.productionIntent(
                for: project.id
            )?.isLinkFirstClip != true {
                Button {
                    presentVideoPicker()
                } label: {
                    Label(
                        "Videodatei hinzufügen",
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.bordered)
            }

            if currentStage != .published {
                Button {
                    if session.activeProject?.isPaused == true {
                        if session.setProjectPaused(
                            project.id,
                            paused: false
                        ) {
                            state.resumeProcessing()
                        }
                    } else {
                        activeProcessingTask?.cancel()
                        activeProcessingTask = nil
                        state.requestStopProcessing()
                        _ = session.setProjectPaused(
                            project.id,
                            paused: true
                        )
                    }
                } label: {
                    Label(
                        session.activeProject?.isPaused == true
                            ? "Fortsetzen"
                            : "Pausieren",
                        systemImage:
                            session.activeProject?.isPaused == true
                            ? "play.fill"
                            : "pause.fill"
                    )
                }
                .buttonStyle(.bordered)
            }

            if state.renderArtifact != nil {
                Button {
                    if currentStage == .editing {
                        if session.advanceActiveProject(to: .packaging) {
                            showPackagingReview = true
                        }
                    } else {
                        showPackagingReview = true
                    }
                } label: {
                    Label("Veröffentlichen", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(BlackstockDesign.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(BlackstockDesign.raisedSurface)
    }

    private func sourceContext(_ source: MediaSourceReference) -> some View {
        let resolution = MediaSourceResolver().resolve(
            source,
            approvedProvider: nil
        )
        let isLinkFirstClip =
            session.productionIntent(for: project.id)?.isLinkFirstClip == true
        let hasBoundAuthorizedMedia =
            state.asset?.originSource?.id == source.id
            && state.asset?.mayEnterProduction == true
        let clipPreparation =
            OpportunityClipPreparationPlanner().snapshot(
                source: source,
                resolution: resolution,
                hasBoundAuthorizedMedia: hasBoundAuthorizedMedia,
                isGeneratingClips:
                    state.isGeneratingClipCandidates,
                clipCount: state.localClipCandidates.count
            )
        return HStack(spacing: 12) {
            Image(
                systemName:
                    source.provider == .youtube
                    ? "play.rectangle"
                    : "link"
            )
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text("Quelle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if isLinkFirstClip {
                        Label(
                            "Clip",
                            systemImage: "scissors"
                        )
                        .font(.caption2.weight(.semibold))
                    }
                }

                Text(
                    source.provider == .youtube
                    ? "YouTube-Video "
                        + (source.externalID ?? "")
                    : "Produktionsquelle verbunden"
                )
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                if isLinkFirstClip {
                    Label(
                        clipPreparation.status.germanTitle,
                        systemImage:
                            clipPreparationIcon(
                                clipPreparation.status
                            )
                    )
                    .font(.caption.weight(.semibold))

                    Text(
                        hasBoundAuthorizedMedia
                            ? "Videoquelle bereit. Blackstock kann das Material jetzt analysieren und clippen."
                            : (
                                ingestWatcher.isWatching
                                ? "Quellen-Monitor aktiv. Blackstock übernimmt passende Dateien aus dem Ingest-Ordner automatisch."
                                : "Noch keine nutzbare Medienquelle gebunden. Öffne den Downloader, den Ingest-Ordner oder wähle eine alternative Quelle."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Label(
                            ingestWatcher.isWatching
                                ? "Quellen-Monitor aktiv"
                                : "Quellen-Monitor pausiert",
                            systemImage:
                                ingestWatcher.isWatching
                                ? "dot.radiowaves.left.and.right"
                                : "pause.circle"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                        if let lastEventAt =
                                ingestWatcher.lastEventAt {
                            Text(
                                "Letzte Änderung "
                                + lastEventAt.formatted(
                                    date: .omitted,
                                    time: .shortened
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Button(
                            ingestWatcher.isWatching
                                ? "Pausieren"
                                : "Starten"
                        ) {
                            if ingestWatcher.isWatching {
                                ingestWatcher.stop()
                            } else {
                                startIngestWatcher()
                            }
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }

                    if clipPreparation.status
                            == .productionMediaRequired,
                       currentStage == .production {
                        HStack(spacing: 8) {
                            Button {
                                Task {
                                    await attemptAutomaticOriginalBinding()
                                }
                            } label: {
                                HStack {
                                    if isResolvingAutomaticSource {
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                    Label(
                                        isResolvingAutomaticSource
                                            ? "Quelle wird geprüft …"
                                            : "Quelle erneut prüfen",
                                        systemImage:
                                            "arrow.clockwise"
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(
                                isResolvingAutomaticSource
                            )

                            Button {
                                sourceDownloadURLText = ""
                                sourceDownloadMessage = nil
                                showSourceDownloader = true
                            } label: {
                                Label(
                                    "Downloader",
                                    systemImage:
                                        "arrow.down.circle"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Menu {

                                Button {
                                    presentOriginalMediaLibraryPicker()
                                } label: {
                                    Label(
                                        "Lokale Mediathek verbinden",
                                        systemImage:
                                            "folder.badge.plus"
                                    )
                                }
                                Button {
                                    presentVideoPicker()
                                } label: {
                                    Label(
                                        "Datei als alternative Quelle wählen",
                                        systemImage:
                                            "film.stack"
                                    )
                                }
                            } label: {
                                Label(
                                    "Alternative Quelle",
                                    systemImage:
                                        "ellipsis.circle"
                                )
                            }
                            .menuStyle(.borderlessButton)
                            .controlSize(.small)
                        }
                    }

                    if clipPreparation.status
                            == .localProcessingReady,
                       currentStage == .editing {
                        Button {
                            Task {
                                await state
                                    .generateLocalClipCandidates(
                                        localeIdentifier:
                                            speechLocaleIdentifier
                                    )
                            }
                        } label: {
                            Label(
                                "Lokale Clips erzeugen",
                                systemImage: "scissors"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(
                            state.isGeneratingClipCandidates
                        )
                    }
                } else {
                    Text(
                        hasBoundAuthorizedMedia
                            ? "Die Videodatei ist mit diesem Projekt verknüpft."
                            : resolution.explanation
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Quelldetails") {
                    Text(source.pageURL.absoluteString)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 3)
                }
                .font(.caption2)
            }

            Spacer()

            if source.provider == .youtube,
               let videoID = source.externalID {
                VStack(alignment: .trailing, spacing: 6) {
                    YouTubeEmbeddedPlayer(videoID: videoID)
                        .frame(width: 220, height: 124)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 10)
                        )
                    Button("Auf YouTube ansehen") {
                        NSWorkspace.shared.open(source.pageURL)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.018))
    }

    private func clipPreparationIcon(
        _ status: OpportunityClipPreparationStatus
    ) -> String {
        switch status {
        case .resolvingSource:
            return "arrow.triangle.2.circlepath"
        case .productionMediaRequired:
            return "film.stack"
        case .localProcessingReady:
            return "checkmark.circle"
        case .generatingClips:
            return "waveform.badge.magnifyingglass"
        case .clipsAvailable:
            return "checkmark.seal"
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let source = opportunitySource,
           session.productionIntent(
                for: project.id
           )?.isLinkFirstClip == true {
            VStack(spacing: 18) {
                Spacer()

                if source.provider == .youtube,
                   let videoID = source.externalID {
                    YouTubeEmbeddedPlayer(videoID: videoID)
                        .frame(maxWidth: 720)
                        .aspectRatio(
                            16.0 / 9.0,
                            contentMode: .fit
                        )
                        .background(
                            BlackstockDesign.mediaSurface
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius:
                                    BlackstockDesign.cornerRadius,
                                style: .continuous
                            )
                        )
                }

                Text("Video ausgewählt")
                    .font(.title2.bold())

                Text(
                    isResolvingAutomaticSource
                        ? "Blackstock prüft gerade verfügbare lokale Quellen für dieses Video."
                        : "Das Video bleibt ausgewählt und deine einmalige Nutzungsbestätigung gilt weiter. Speichere eine passende Videodatei in „Downloads/Blackstock Ingest“ – Blackstock erkennt sie automatisch und setzt den Clip-Workflow ohne weiteren Dateidialog fort."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await attemptAutomaticOriginalBinding()
                        }
                    } label: {
                        HStack {
                            if isResolvingAutomaticSource {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label(
                                isResolvingAutomaticSource
                                    ? "Quelle wird geprüft …"
                                    : "Quelle erneut prüfen",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isResolvingAutomaticSource
                    )

                    Button {
                        sourceDownloadURLText = ""
                        sourceDownloadMessage = nil
                        showSourceDownloader = true
                    } label: {
                        Label(
                            "Downloader",
                            systemImage:
                                "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    if let ingestURL =
                            session.automaticIngestDirectoryURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [ingestURL]
                            )
                        } label: {
                            Label(
                                "Ingest-Ordner öffnen",
                                systemImage: "folder.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                    }

                    Menu {
                        Button {
                            sourceDownloadURLText = ""
                            sourceDownloadMessage = nil
                            showSourceDownloader = true
                        } label: {
                            Label(
                                "Downloadquelle öffnen",
                                systemImage:
                                    "arrow.down.circle"
                            )
                        }

                        Divider()

                        Button {
                            presentOriginalMediaLibraryPicker()
                        } label: {
                            Label(
                                "Lokale Mediathek verbinden",
                                systemImage:
                                    "folder.badge.plus"
                            )
                        }
                        Button {
                            presentVideoPicker()
                        } label: {
                            Label(
                                "Datei als alternative Quelle wählen",
                                systemImage:
                                    "film.stack"
                            )
                        }
                    } label: {
                        Label(
                            "Alternative Quelle",
                            systemImage: "ellipsis.circle"
                        )
                    }
                    .menuStyle(.borderlessButton)

                    Button("Auf YouTube ansehen") {
                        NSWorkspace.shared.open(
                            source.pageURL
                        )
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        } else {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "film.stack")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Video hinzufügen")
                    .font(.title2.bold())
                Text(
                    "Füge die Videodatei hinzu, die du bearbeiten möchtest."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
                Button("Video auswählen …") {
                    presentVideoPicker()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showOptionalCapture.toggle()
                } label: {
                    Label(
                        showOptionalCapture
                            ? "Eigene Aufnahme ausblenden"
                            : "Optionale Aufnahme",
                        systemImage:
                            showOptionalCapture
                            ? "chevron.up"
                            : "video.badge.plus"
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if showOptionalCapture {
                    CaptureCapabilityPanel { url, kind in
                        pendingURL = url
                        pendingCaptureKind = kind
                        if session.workspaceRightsAttestation?
                            .permitsUserDirectedProduction
                            == true {
                            importPendingMedia()
                        } else {
                            rightsConfirmed = false
                            showRightsSheet = true
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.top, 4)
                }

                Spacer()
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    private func editor(_ asset: ProductionMediaAsset) -> some View {
        HSplitView {
            VStack(spacing: 14) {
                ZStack(alignment: .bottom) {
                    VideoPlayer(player: state.player)
                        .accessibilityLabel("Video-Vorschau des aktuellen Schnitts")

                    if state.previewedLocalClipCandidateID == nil {
                        textOverlayPreview
                    }

                    if state.burnInCaptionsEnabled,
                       state.previewedLocalClipCandidateID == nil {
                        captionPreviewOverlay
                    }
                }
                .frame(minWidth: 680, minHeight: 390)
                .background(BlackstockDesign.mediaSurface)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: BlackstockDesign.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: BlackstockDesign.cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(BlackstockDesign.subtleBorder)
                )

                timeline(asset)
                    .frame(height: 112)

                HStack(spacing: 8) {
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
                        Label("Video fertig", systemImage: "checkmark.seal.fill")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text(String(artifact.sha256.prefix(12)) + "…")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button("Weiter zum Veröffentlichen") {
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
            .frame(minWidth: 760)
            .background(BlackstockDesign.canvas)

            inspector(asset)
                .frame(minWidth: 320, idealWidth: 350, maxWidth: 400)
                .background(BlackstockDesign.raisedSurface)
        }
    }

    private var localClipCandidatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clip-Vorschläge")
                .font(.headline)

            Text("Blackstock findet die stärksten Ausschnitte, bereitet Hochkantformat und Untertitel vor und rendert daraus fertige Clips. Du kannst jeden Schritt anschließend ändern.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    startProcessing {
                        await state.createAutomaticHighlights(
                            localeIdentifier:
                                speechLocaleIdentifier
                        )
                    }
                } label: {
                    HStack {
                        if state.isCreatingAutomaticHighlights {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Label(
                            state.isCreatingAutomaticHighlights
                                ? "Highlights werden erstellt …"
                                : "Highlights automatisch erstellen",
                            systemImage: "sparkles.rectangle.stack"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(BlackstockDesign.accent)
                .disabled(
                    state.isCreatingAutomaticHighlights
                    || state.isGeneratingClipCandidates
                    || !editingEnabled
                )

                Button {
                    startProcessing {
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
                                ? "Clips werden gesucht …"
                                : "Clips manuell prüfen",
                            systemImage: "scissors"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    state.isCreatingAutomaticHighlights
                    || state.isGeneratingClipCandidates
                    || !editingEnabled
                )
            }

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
                    "Vorschlag \(index + 1)"
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
                                state.saveLocalClipCandidate(
                                    candidate
                                )
                            } label: {
                                Label(
                                    "In Clip-Liste speichern",
                                    systemImage:
                                        "tray.and.arrow.down"
                                )
                            }
                            .buttonStyle(.bordered)
                            .disabled(!editingEnabled)

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

            if !state.savedClipSelections.isEmpty {
                Divider()

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    HStack {
                        Text("Gespeicherte Clips")
                            .font(
                                .subheadline.weight(
                                    .semibold
                                )
                            )
                        Spacer()
                        Text(
                            "\(state.savedClipSelections.count)"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await state
                                    .renderAllSavedClipSelections()
                            }
                        } label: {
                            HStack {
                                if state.isRenderingSavedClipBatch {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Label(
                                    state.isRenderingSavedClipBatch
                                        ? "Alle werden erstellt …"
                                        : "Alle erstellen",
                                    systemImage:
                                        "square.stack.3d.up"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            state.isRenderingSavedClipBatch
                            || state.renderingSavedClipID != nil
                            || !editingEnabled
                        )

                        Button {
                            showClipExportFolderImporter = true
                        } label: {
                            HStack {
                                if state.isExportingSavedClipBatch {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Label(
                                    state.isExportingSavedClipBatch
                                        ? "Exportiert …"
                                        : "Exportieren …",
                                    systemImage:
                                        "square.and.arrow.up"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            state.isExportingSavedClipBatch
                            || !state.savedClipSelections
                                .contains {
                                    $0.renderArtifact?
                                        .hasCurrentTechnicalValidation
                                        == true
                                }
                        )
                    }

                    ForEach(
                        state.savedClipSelections
                    ) { selection in
                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {
                            TextField(
                                "Clip-Name",
                                text: Binding(
                                    get: {
                                        state.savedClipSelections
                                            .first(
                                                where: {
                                                    $0.id
                                                        == selection.id
                                                }
                                            )?
                                            .title
                                            ?? ""
                                    },
                                    set: { value in
                                        state.renameSavedClipSelection(
                                            id: selection.id,
                                            title: value
                                        )
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline.weight(.semibold))
                            .accessibilityLabel(
                                "Name des gespeicherten Clips"
                            )

                            HStack {
                                Text(
                                    timeLabel(
                                        selection.sourceRange
                                            .startSeconds
                                    )
                                    + " – "
                                    + timeLabel(
                                        selection.sourceRange
                                            .endSeconds
                                    )
                                )
                                .font(
                                    .caption.weight(
                                        .semibold
                                    )
                                    .monospacedDigit()
                                )

                                Spacer()

                                Text(
                                    "\(selection.wordCount) Wörter"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Text(
                                selection.transcriptPreview
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                            VStack(
                                alignment: .leading,
                                spacing: 6
                            ) {
                                HStack {
                                    Button {
                                        Task {
                                            await state
                                                .previewSavedClipSelection(
                                                    selection
                                                )
                                        }
                                    } label: {
                                        Label(
                                            state.previewedLocalClipCandidateID
                                                == selection.id
                                                ? "Vorschau läuft"
                                                : "Vorschau",
                                            systemImage: "play.circle"
                                        )
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        Task {
                                            await state
                                                .applySavedClipSelection(
                                                    selection
                                                )
                                        }
                                    } label: {
                                        Label(
                                            "Übernehmen",
                                            systemImage:
                                                "checkmark.circle"
                                        )
                                    }
                                    .buttonStyle(
                                        .borderedProminent
                                    )
                                    .disabled(!editingEnabled)
                                }

                                HStack {
                                    Button {
                                        Task {
                                            await state
                                                .renderSavedClipSelection(
                                                    selection
                                                )
                                        }
                                    } label: {
                                        HStack {
                                            if state.renderingSavedClipID
                                                == selection.id {
                                                ProgressView()
                                                    .controlSize(.small)
                                            }
                                            Label(
                                                state.renderingSavedClipID
                                                    == selection.id
                                                    ? "Wird erstellt …"
                                                    : "Datei erstellen",
                                                systemImage: "film"
                                            )
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(
                                        state.renderingSavedClipID != nil
                                        || state.isRenderingSavedClipBatch
                                        || !editingEnabled
                                    )

                                    Menu {
                                        Button {
                                            state.loadSavedClipSelection(
                                                selection
                                            )
                                        } label: {
                                            Label(
                                                "In Timeline laden",
                                                systemImage:
                                                    "slider.horizontal.3"
                                            )
                                        }

                                        Button(
                                            "Entfernen",
                                            role: .destructive
                                        ) {
                                            state.removeSavedClipSelection(
                                                selection
                                            )
                                        }
                                    } label: {
                                        Label(
                                            "Mehr",
                                            systemImage:
                                                "ellipsis.circle"
                                        )
                                    }
                                    .menuStyle(.borderlessButton)
                                    .disabled(!editingEnabled)
                                }
                            }

                            if let artifact =
                                selection.renderArtifact {
                                VStack(
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    Label(
                                        "Clip-Datei bereit",
                                        systemImage:
                                            "checkmark.seal.fill"
                                    )
                                    .font(
                                        .caption.weight(
                                            .semibold
                                        )
                                    )
                                    Text(
                                        artifact.fileURL
                                            .lastPathComponent
                                    )
                                    .font(
                                        .caption2.monospaced()
                                    )
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                    Button {
                                        Task {
                                            await state
                                                .useSavedClipForPackaging(
                                                    selection
                                                )
                                        }
                                    } label: {
                                        Label(
                                            "Zum Veröffentlichen verwenden",
                                            systemImage:
                                                "shippingbox"
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(
                                        !artifact
                                            .hasCurrentTechnicalValidation
                                        || !editingEnabled
                                    )
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            Color.primary.opacity(0.025),
                            in: RoundedRectangle(
                                cornerRadius: 10
                            )
                        )
                    }

                    Text("„In Timeline laden“ übernimmt die Auswahl in die Schnittregler. Mit „Als Trim setzen“ wird der Schnitt angewendet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("„Exportieren …“ kopiert alle bereits validiert gerenderten Clips in deinen Zielordner. Vorhandene Clip-Transkripte werden als WebVTT mit ausgegeben; eine Blackstock-JSON-Datei bindet Dateinamen, Quell-Zeitbereiche und Render-SHA-256 zusammen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                Text("Die Vorschau verändert dein Video nicht. Mit „Diesen Ausschnitt übernehmen“ wird der Schnitt angewendet und bleibt rückgängig machbar.")
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

            Text("Schnittänderungen bleiben rückgängig machbar.")
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

                if !state.supplementalCaptures.isEmpty
                    || session.productionIntent(
                        for: project.id
                    )?.isLinkFirstClip != true {
                    Divider()
                    supplementalCapturesSection
                }

                Divider()

                storyboardSection

                Divider()

                localClipCandidatesSection

                Divider()

                textOverlaySection(asset)

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

                    Menu {
                        ForEach(
                            CreatorOutputPreset.allCases,
                            id: \.self
                        ) { preset in
                            Button {
                                state.prepareOutputPreset(
                                    preset
                                )
                            } label: {
                                Text(
                                    preset.germanTitle
                                )
                            }
                        }
                    } label: {
                        Label(
                            "Ausgabe-Preset vorbereiten",
                            systemImage: "rectangle.3.group"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(!editingEnabled)

                    Text("Wähle YouTube 16:9, Shorts/Reels 9:16 oder Social 1:1. Mit „Ausschnitt anwenden“ wird das Format übernommen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

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

                    Text("Blackstock kann den Bildausschnitt vorschlagen. Mit „Ausschnitt anwenden“ übernimmst du ihn für Vorschau und Export.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Hauptton")
                        .font(.headline)

                    HStack {
                        Text("Lautstärke")
                        Spacer()
                        Text(
                            "\(Int((state.masterVolume * 100).rounded())) %"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $state.masterVolume,
                        in: 0...1,
                        step: 0.05
                    )
                    .disabled(!editingEnabled)
                    .accessibilityLabel("Lautstärke des Haupttons")
                    .accessibilityValue(
                        "\(Int((state.masterVolume * 100).rounded())) Prozent"
                    )

                    Button {
                        Task {
                            await state.applyMasterVolume()
                        }
                    } label: {
                        Label(
                            "Lautstärke anwenden",
                            systemImage: "speaker.wave.2"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        !editingEnabled
                        || abs(
                            state.masterVolume
                            - state.appliedMasterVolume
                        ) < 0.001
                    )

                    Text("Die Änderung bleibt rückgängig machbar. Zusatzspuren behalten ihre eigene Lautstärke; Blackstock prüft anschließend den fertigen Tonmix.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Export")
                        .font(.headline)

                    Picker(
                        "Qualität",
                        selection: Binding(
                            get: {
                                state.renderPreset
                            },
                            set: { newValue in
                                guard state.renderPreset
                                    != newValue else {
                                    return
                                }
                                state.renderPreset = newValue
                                state.renderArtifact = nil
                                state.invalidateSavedClipRenders()
                            }
                        )
                    ) {
                        Text("1080p").tag(LocalRenderPreset.hd1080)
                        Text("4K").tag(LocalRenderPreset.uhd4K)
                    }
                    .pickerStyle(.segmented)

                    Button {
                        startProcessing {
                            await state.render(
                                projectID: project.id
                            )
                        }
                    } label: {
                        HStack {
                            if state.isRendering {
                                ProgressView().controlSize(.small)
                            }
                            Label(
                                state.isRendering ? "Video wird erstellt …" : "Video erstellen",
                                systemImage: "film"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isRendering || !editingEnabled)

                    Text("Blackstock erstellt das Video lokal auf deinem Mac.")
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
                                    "Sichtbare Untertitel ins Video rendern"
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

                        if state.burnInCaptionsEnabled {
                            Picker(
                                "Untertitelstil",
                                selection: Binding(
                                    get: {
                                        state.captionVisualStyle
                                    },
                                    set: {
                                        state.setCaptionVisualStyle(
                                            $0
                                        )
                                    }
                                )
                            ) {
                                ForEach(
                                    CaptionVisualStyle.allCases,
                                    id: \.self
                                ) { style in
                                    Text(style.germanTitle)
                                        .tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!editingEnabled)

                            Text(
                                state.captionVisualStyle
                                    .germanExplanation
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        DisclosureGroup("Untertitel bearbeiten") {
                            VStack(
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(transcript.segments) {
                                    segment in
                                    Button {
                                        beginCaptionEdit(
                                            segment
                                        )
                                    } label: {
                                        HStack {
                                            VStack(
                                                alignment: .leading,
                                                spacing: 2
                                            ) {
                                                Text(segment.text)
                                                    .lineLimit(2)
                                                Text(
                                                    timeLabel(
                                                        segment.startSeconds
                                                    )
                                                    + " – "
                                                    + timeLabel(
                                                        segment.startSeconds
                                                        + segment.durationSeconds
                                                    )
                                                )
                                                .font(
                                                    .caption2
                                                        .monospacedDigit()
                                                )
                                                .foregroundStyle(
                                                    .secondary
                                                )
                                            }
                                            Spacer()
                                            if segment
                                                .wasEditedByUser {
                                                Label(
                                                    "Korrigiert",
                                                    systemImage:
                                                        "checkmark.circle"
                                                )
                                                .font(.caption2)
                                            } else {
                                                Image(
                                                    systemName:
                                                        "pencil"
                                                )
                                                .foregroundStyle(
                                                    .secondary
                                                )
                                                .accessibilityLabel(
                                                    "Untertitelsegment bearbeiten"
                                                )
                                            }
                                        }
                                        .contentShape(
                                            Rectangle()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!editingEnabled)
                                }

                                if let selectedID =
                                        selectedCaptionSegmentID,
                                   transcript.segments
                                    .contains(
                                        where: {
                                            $0.id
                                                == selectedID
                                        }
                                    ) {
                                    Divider()

                                    Text("Segment korrigieren")
                                        .font(
                                            .caption.weight(
                                                .semibold
                                            )
                                        )

                                    TextField(
                                        "Untertiteltext",
                                        text: $captionEditText,
                                        axis: .vertical
                                    )
                                    .lineLimit(2...5)
                                    .disabled(!editingEnabled)

                                    HStack {
                                        TextField(
                                            "Start in Sekunden",
                                            value:
                                                $captionEditStartSeconds,
                                            format:
                                                .number.precision(
                                                    .fractionLength(
                                                        2
                                                    )
                                                )
                                        )
                                        TextField(
                                            "Dauer in Sekunden",
                                            value:
                                                $captionEditDurationSeconds,
                                            format:
                                                .number.precision(
                                                    .fractionLength(
                                                        2
                                                    )
                                                )
                                        )
                                    }
                                    .textFieldStyle(
                                        .roundedBorder
                                    )
                                    .disabled(!editingEnabled)

                                    HStack {
                                        Button(
                                            "Änderung speichern"
                                        ) {
                                            state.updateCaptionSegment(
                                                id: selectedID,
                                                text:
                                                    captionEditText,
                                                startSeconds:
                                                    captionEditStartSeconds,
                                                durationSeconds:
                                                    captionEditDurationSeconds
                                            )
                                            if state.errorMessage
                                                == nil {
                                                selectedCaptionSegmentID =
                                                    nil
                                            }
                                        }
                                        .buttonStyle(
                                            .borderedProminent
                                        )
                                        .disabled(
                                            !editingEnabled
                                            || captionEditText
                                                .trimmingCharacters(
                                                    in:
                                                        .whitespacesAndNewlines
                                                )
                                                .isEmpty
                                        )

                                        Button("Abbrechen") {
                                            selectedCaptionSegmentID =
                                                nil
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    Text(
                                        "Text und Timing werden lokal in Transkript und WebVTT gespeichert. Überlappende oder außerhalb des aktuellen Schnitts liegende Segmente werden abgelehnt."
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(
                            .caption.weight(.semibold)
                        )

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
                                    Text("Quelle: \(advisory.source)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                            }
                            .font(.caption.weight(.semibold))
                        }

                        Text("Blackstock analysiert die Videostruktur lokal. Vorschläge bleiben optional und können jederzeit geändert werden.")
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

    private func textOverlaySection(
        _ asset: ProductionMediaAsset
    ) -> some View {
        let duration = max(
            state.currentOutputDurationSeconds,
            0.05
        )
        let startUpperBound = max(
            duration - 0.05,
            0.05
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Text-Overlay")
                .font(.headline)

            TextField(
                "Text im Video",
                text: $state.overlayText
            )
            .textFieldStyle(.roundedBorder)
            .disabled(!editingEnabled)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Start")
                    Spacer()
                    Text(timeLabel(min(
                        max(state.overlayStart, 0),
                        startUpperBound
                    )))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: {
                            min(
                                max(state.overlayStart, 0),
                                startUpperBound
                            )
                        },
                        set: { newValue in
                            state.overlayStart = newValue
                            state.overlayEnd = min(
                                max(
                                    state.overlayEnd,
                                    newValue + 0.05
                                ),
                                duration
                            )
                        }
                    ),
                    in: 0...startUpperBound
                )
                .accessibilityLabel("Start des Text-Overlays")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Ende")
                    Spacer()
                    Text(timeLabel(min(
                        max(state.overlayEnd, 0.05),
                        duration
                    )))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: {
                            min(
                                max(state.overlayEnd, 0.05),
                                duration
                            )
                        },
                        set: { newValue in
                            state.overlayEnd = newValue
                            state.overlayStart = min(
                                state.overlayStart,
                                max(newValue - 0.05, 0)
                            )
                        }
                    ),
                    in: 0.05...duration
                )
                .accessibilityLabel("Ende des Text-Overlays")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Position von oben")
                    Spacer()
                    Text(
                        String(
                            format: "%.0f%%",
                            state.overlayVerticalPosition
                                * 100
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Slider(
                    value: $state.overlayVerticalPosition,
                    in: 0.05...0.95
                )
                .accessibilityLabel(
                    "Vertikale Position des Text-Overlays"
                )
                .accessibilityValue(
                    String(
                        format: "%.0f Prozent von oben",
                        state.overlayVerticalPosition * 100
                    )
                )
            }

            Button {
                Task {
                    await state.applyTextOverlay()
                }
            } label: {
                Label(
                    "Overlay anwenden",
                    systemImage: "text.bubble"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                !editingEnabled
                || state.overlayText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )

            let overlays = TextOverlayPlanner().cues(
                operations: state.graph.currentOperations,
                outputDurationSeconds:
                    state.currentOutputDurationSeconds
            )
            if !overlays.isEmpty {
                Divider()
                Text("Aktive Overlays")
                    .font(.caption.weight(.semibold))

                ForEach(overlays) { cue in
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(cue.text)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        Text(
                            timeLabel(cue.startSeconds)
                            + " – "
                            + timeLabel(
                                cue.startSeconds
                                + cue.durationSeconds
                            )
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                Text("Text-Overlays können jederzeit rückgängig gemacht oder wiederhergestellt werden.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Die Studio-Vorschau zeigt dieselben Zeitfenster und dieselbe vertikale Position. Beim finalen Render wird der Text lokal in die Videopixel eingebrannt.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var textOverlayPreview: some View {
        GeometryReader { geometry in
            TimelineView(
                .periodic(
                    from: .now,
                    by: 0.10
                )
            ) { _ in
                let timeSeconds = max(
                    CMTimeGetSeconds(
                        state.player.currentTime()
                    ),
                    0
                )
                let cues = TextOverlayPlanner().cues(
                    operations: state.graph.currentOperations,
                    outputDurationSeconds:
                        state.currentOutputDurationSeconds
                )
                ForEach(
                    cues.filter {
                        timeSeconds >= $0.startSeconds
                        && timeSeconds
                            < $0.startSeconds
                            + $0.durationSeconds
                    }
                ) { cue in
                    Text(cue.text)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(
                            maxWidth:
                                geometry.size.width * 0.72
                        )
                        .background(
                            Color.black.opacity(0.52),
                            in: RoundedRectangle(
                                cornerRadius: 12
                            )
                        )
                        .shadow(radius: 3, y: -1)
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height
                                * cue.normalizedYFromTop
                        )
                        .accessibilityLabel(
                            "Text-Overlay: \(cue.text)"
                        )
                }
            }
        }
        .allowsHitTesting(false)
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
                        .font(
                            previewCaptionFont(
                                state.captionVisualStyle
                            )
                        )
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(
                            .horizontal,
                            previewCaptionHorizontalPadding(
                                state.captionVisualStyle
                            )
                        )
                        .padding(
                            .vertical,
                            previewCaptionVerticalPadding(
                                state.captionVisualStyle
                            )
                        )
                        .frame(
                            maxWidth:
                                previewCaptionMaxWidth(
                                    state.captionVisualStyle
                                )
                        )
                        .background(
                            Color.black.opacity(
                                state.captionVisualStyle
                                    .backgroundOpacity
                            ),
                            in: RoundedRectangle(
                                cornerRadius:
                                    previewCaptionCornerRadius(
                                        state.captionVisualStyle
                                    )
                            )
                        )
                        .shadow(
                            radius:
                                previewCaptionShadowRadius(
                                    state.captionVisualStyle
                                ),
                            y: -1
                        )
                        .padding(.horizontal, 28)
                        .padding(
                            .bottom,
                            previewCaptionBottomPadding(
                                state.captionVisualStyle
                            )
                        )
                        .accessibilityLabel(
                            "Eingebrannter Untertitel: \(text)"
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func beginCaptionEdit(
        _ segment: TranscriptSegment
    ) {
        selectedCaptionSegmentID = segment.id
        captionEditText = segment.text
        captionEditStartSeconds =
            segment.startSeconds
        captionEditDurationSeconds =
            segment.durationSeconds
    }

    private func previewCaptionFont(
        _ style: CaptionVisualStyle
    ) -> Font {
        switch style.fontWeight {
        case .semibold:
            return style == .minimal
                ? .callout.weight(.semibold)
                : .title3.weight(.semibold)
        case .bold:
            return .title3.bold()
        case .heavy:
            return .title2.weight(.heavy)
        }
    }

    private func previewCaptionHorizontalPadding(
        _ style: CaptionVisualStyle
    ) -> CGFloat {
        switch style {
        case .clear: return 18
        case .strong: return 22
        case .minimal: return 14
        }
    }

    private func previewCaptionVerticalPadding(
        _ style: CaptionVisualStyle
    ) -> CGFloat {
        switch style {
        case .clear: return 10
        case .strong: return 13
        case .minimal: return 8
        }
    }

    private func previewCaptionMaxWidth(
        _ style: CaptionVisualStyle
    ) -> CGFloat {
        switch style {
        case .clear: return 560
        case .strong: return 600
        case .minimal: return 500
        }
    }

    private func previewCaptionCornerRadius(
        _ style: CaptionVisualStyle
    ) -> CGFloat {
        switch style {
        case .clear: return 12
        case .strong: return 16
        case .minimal: return 9
        }
    }

    private func previewCaptionShadowRadius(
        _ style: CaptionVisualStyle
    ) -> CGFloat {
        switch style {
        case .clear: return 3
        case .strong: return 5
        case .minimal: return 2
        }
    }

    private func previewCaptionBottomPadding(
        _ style: CaptionVisualStyle
    ) -> CGFloat {
        switch style {
        case .clear: return 24
        case .strong: return 30
        case .minimal: return 20
        }
    }

    private func activeCaptionText(
        transcript: LocalTranscript,
        timeSeconds: Double
    ) -> String? {
        guard let segment = transcript.segments.first(
            where: {
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
            }
        ) else {
            return nil
        }

        let text = segment.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return text.isEmpty ? nil : text
    }

    private var sourceDownloaderSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quelle herunterladen")
                        .font(.title2.bold())
                    Text(
                        "Direkte oder autorisierte Medienquelle herunterladen und anschließend automatisch in Blackstock übernehmen."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let source = opportunitySource {
                GroupBox("Ausgewähltes Video") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.title)
                            .font(.headline)
                        Text(source.pageURL.absoluteString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Download-URL")
                    .font(.caption.weight(.semibold))
                TextField(
                    "https://…/video.mp4",
                    text: $sourceDownloadURLText
                )
                .textFieldStyle(.roundedBorder)

                Text(
                    "Hier gehört eine direkte oder von einem verbundenen Anbieter freigegebene Medien-URL hinein. Ein normaler youtube.com/watch-Link ist keine direkte Downloadquelle."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        sourceDownloader.state.germanTitle,
                        systemImage: downloadStateIcon
                    )
                    .font(.callout.weight(.semibold))
                    Spacer()
                    Text(
                        String(
                            format: "%.0f%%",
                            sourceDownloader.progress * 100
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                ProgressView(
                    value: sourceDownloader.progress
                )

                if let destination =
                        sourceDownloader.destinationURL {
                    Text(
                        "Ziel: " + destination.path
                    )
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
            }

            if let sourceDownloadMessage {
                Label(
                    sourceDownloadMessage,
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("Schließen") {
                    showSourceDownloader = false
                }

                Spacer()

                switch sourceDownloader.state {
                case .downloading:
                    Button("Pausieren") {
                        sourceDownloader.pause()
                    }
                    .buttonStyle(.bordered)

                    Button(
                        "Abbrechen",
                        role: .destructive
                    ) {
                        sourceDownloader.cancel()
                    }
                    .buttonStyle(.bordered)

                case .paused:
                    Button("Fortsetzen") {
                        sourceDownloader.resume()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(
                        "Abbrechen",
                        role: .destructive
                    ) {
                        sourceDownloader.cancel()
                    }
                    .buttonStyle(.bordered)

                default:
                    Button {
                        startSourceDownload()
                    } label: {
                        Label(
                            "Herunterladen",
                            systemImage:
                                "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        sourceDownloadURLText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private var downloadStateIcon: String {
        switch sourceDownloader.state {
        case .idle:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func startSourceDownload() {
        sourceDownloadMessage = nil
        let rawValue = sourceDownloadURLText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard let remoteURL = URL(
            string: rawValue
        ),
        let scheme = remoteURL.scheme?.lowercased(),
        scheme == "https" || scheme == "http" else {
            sourceDownloadMessage =
                "Gib eine gültige HTTP- oder HTTPS-Download-URL ein."
            return
        }

        let host = remoteURL.host?
            .lowercased() ?? ""
        if host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtu.be"
            || host.hasSuffix(".youtu.be") {
            sourceDownloadMessage =
                "Ein normaler YouTube-Watch-Link ist keine direkte Medien-Downloadquelle. Verwende eine direkte oder autorisierte Medien-URL."
            return
        }

        guard let ingestDirectory =
                session.automaticIngestDirectoryURL else {
            sourceDownloadMessage =
                "Der Blackstock-Ingest-Ordner konnte nicht erstellt werden."
            return
        }

        var fileName = remoteURL
            .lastPathComponent
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        if fileName.isEmpty
            || fileName == "/" {
            fileName =
                (opportunitySource?.externalID
                    ?? UUID().uuidString)
                + ".mp4"
        }
        if URL(
            fileURLWithPath: fileName
        ).pathExtension.isEmpty {
            fileName += ".mp4"
        }

        let destination = ingestDirectory
            .appendingPathComponent(fileName)

        sourceDownloader.start(
            remoteURL: remoteURL,
            destinationURL: destination
        )
    }

    private var rightsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Einmalige Nutzungsverantwortung")
                .font(.title2.bold())

            Text("Diese Erklärung gilt danach für den gesamten ausgewählten Blackstock-Arbeitsbereich.")
                .foregroundStyle(.secondary)

            Toggle(isOn: $rightsConfirmed) {
                Text("Ich verwende Blackstock nur für Inhalte, die ich bearbeiten und veröffentlichen darf, und übernehme die Verantwortung für diese Nutzung.")
                    .font(.callout)
            }

            Text("Blackstock verknüpft Quelle, Projekt und Videodatei automatisch. Eine zusätzliche Lizenzdatei pro Video ist nicht nötig.")
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
                Button("Einmalig bestätigen & fortfahren") {
                    guard rightsConfirmed else { return }
                    guard session
                        .setWorkspaceRightsResponsibilityAccepted(
                            true
                        ) else {
                        return
                    }
                    showRightsSheet = false
                    importPendingMedia()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!rightsConfirmed)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func startIngestWatcher() {
        guard let ingestURL =
                session.automaticIngestDirectoryURL else {
            return
        }
        ingestWatcher.start(
            directoryURL: ingestURL
        ) {
            Task { @MainActor in
                await attemptAutomaticOriginalBinding()
            }
        }
    }

    private func attemptAutomaticOriginalBinding() async {
        guard state.asset == nil,
              session.productionIntent(
                for: project.id
              )?.isLinkFirstClip == true,
              let source = opportunitySource,
              session.workspaceRightsAttestation?
                .permitsUserDirectedProduction == true else {
            return
        }

        isResolvingAutomaticSource = true
        defer {
            isResolvingAutomaticSource = false
        }

        guard let matchedURL =
                await session.resolveOriginalMedia(
                    for: project,
                    source: source
                ) else {
            return
        }

        pendingURL = matchedURL
        pendingCaptureKind = nil
        importPendingMedia()
    }

    private func presentOriginalMediaLibraryPicker() {
        let panel = NSOpenPanel()
        panel.title = "Originalvideo-Ordner auswählen"
        panel.prompt = "Ordner verwenden"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url,
              session.setOriginalMediaLibrary(url) else {
            return
        }

        Task {
            await attemptAutomaticOriginalBinding()
        }
    }

    private func presentVideoPicker() {
        let panel = NSOpenPanel()
        panel.title = "Videodatei auswählen"
        panel.prompt = "Auswählen"
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        pendingURL = url
        pendingCaptureKind = nil

        if session.workspaceRightsAttestation?
            .permitsUserDirectedProduction == true {
            importPendingMedia()
        } else {
            rightsConfirmed = false
            showRightsSheet = true
        }
    }

    private func importPendingMedia() {
        guard let url = pendingURL,
              let attestation =
                session.workspaceRightsAttestation,
              attestation.permitsUserDirectedProduction else {
            return
        }

        let captureKind = pendingCaptureKind
        let sourceReference = opportunitySource
        let sourceEvidence: String
        if let sourceReference {
            let providerReference =
                sourceReference.externalID
                ?? sourceReference.pageURL.absoluteString
            sourceEvidence =
                "Automatisch gebunden an "
                + sourceReference.provider.rawValue
                + ": "
                + providerReference
        } else {
            sourceEvidence =
                "Direkt dem Blackstock-Projekt als Produktionsmedium zugeordnet."
        }

        Task {
            let isSupplementalCapture =
                captureKind == .microphone
                || captureKind == .systemAudio
                || (
                    state.asset != nil
                    && (
                        captureKind == .camera
                        || captureKind == .screen
                    )
                )

            if isSupplementalCapture,
               let captureKind {
                let saved = await state.importSupplementalCapture(
                    url: url,
                    kind: captureKind,
                    projectID: project.id,
                    rightsBasis:
                        "Arbeitsbereich-Nutzererklärung "
                        + attestation.statementVersion,
                    rightsEvidence: sourceEvidence,
                    rightsConfirmed: true
                )
                if saved,
                   let persisted = state.supplementalCaptures.last(
                    where: { $0.kind == captureKind }
                   ) {
                    await BlackstockCaptureHardwareAudit
                        .recordPersistedCapture(
                            kind: captureKind,
                            fileURL: persisted.fileURL,
                            projectID: project.id
                        )
                    try? FileManager.default.removeItem(at: url)
                    BlackstockCaptureHardwareAudit
                        .recordTemporaryCleanup(
                            for: captureKind,
                            temporaryURL: url
                        )
                }
            } else {
                let previousAssetID = state.asset?.id
                await state.importMovie(
                    url: url,
                    projectID: project.id,
                    authorization:
                        .userDeclaredResponsibility,
                    rightsEvidence:
                        "Arbeitsbereich-Nutzererklärung "
                        + attestation.statementVersion
                        + ". "
                        + sourceEvidence,
                    rightsConfirmed: true,
                    originSource: sourceReference
                )
                if let imported = state.asset,
                   imported.id != previousAssetID {
                    if let captureKind {
                        await BlackstockCaptureHardwareAudit
                            .recordPersistedCapture(
                                kind: captureKind,
                                fileURL: imported.sourceURL,
                                projectID: project.id
                            )
                        try? FileManager.default.removeItem(at: url)
                        BlackstockCaptureHardwareAudit
                            .recordTemporaryCleanup(
                                for: captureKind,
                                temporaryURL: url
                            )
                    }
                    if currentStage == .production {
                        if session.productionIntent(
                            for: project.id
                        )?.isLinkFirstClip == true {
                            guard session.advanceActiveProject(
                                to: .preview
                            ) else { return }
                            guard session.advanceActiveProject(
                                to: .storyboard
                            ) else { return }
                            state.loadStoryboard(
                                projectID: project.id
                            )
                            guard session.advanceActiveProject(
                                to: .editing
                            ) else { return }

                            state.resumeProcessing()
                            await state.createAutomaticHighlights(
                                localeIdentifier:
                                    speechLocaleIdentifier
                            )
                        } else {
                            _ = session.advanceActiveProject(
                                to: .preview
                            )
                        }
                    }
                }
            }

            pendingURL = nil
            pendingCaptureKind = nil
        }
    }

    @ViewBuilder
    private var supplementalCapturesSection: some View {
        GroupBox("Zusätzliche Aufnahmen") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.supplementalCaptures) { capture in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(
                                systemName:
                                    supplementalCaptureIcon(
                                        capture.kind
                                    )
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
                                "Nutzererklärung vorhanden",
                                systemImage: "checkmark.shield"
                            )
                            .font(.caption2)
                        }

                        if capture.kind == .microphone
                            || capture.kind == .systemAudio {
                            let setting = state.supplementalAudioSetting(
                                for: capture.id
                            )

                            Toggle(
                                "Im finalen Render mischen",
                                isOn: Binding(
                                    get: {
                                        state.supplementalAudioSetting(
                                            for: capture.id
                                        ).enabled
                                    },
                                    set: {
                                        state.setSupplementalAudioEnabled(
                                            captureID: capture.id,
                                            enabled: $0
                                        )
                                    }
                                )
                            )
                            .font(.caption)
                            .disabled(!editingEnabled)

                            HStack(spacing: 10) {
                                Text("Lautstärke")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Slider(
                                    value: Binding(
                                        get: {
                                            state.supplementalAudioSetting(
                                                for: capture.id
                                            ).volume
                                        },
                                        set: {
                                            state.setSupplementalAudioVolume(
                                                captureID: capture.id,
                                                volume: $0
                                            )
                                        }
                                    ),
                                    in: 0...1,
                                    step: 0.05
                                )
                                .disabled(
                                    !editingEnabled
                                    || !setting.enabled
                                )

                                Text(
                                    "\(Int((setting.volume * 100).rounded())) %"
                                )
                                .font(.caption2.monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                            }
                        }

                        if capture.kind == .camera
                            || capture.kind == .screen {
                            let setting =
                                state.supplementalVideoSetting(
                                    for: capture.id
                                )
                            let outputDuration = max(
                                state.currentOutputDurationSeconds,
                                0.1
                            )
                            let sourceDuration = max(
                                capture.durationSeconds ?? 5,
                                0.1
                            )

                            Toggle(
                                "Als visuelle Einblendung verwenden",
                                isOn: Binding(
                                    get: {
                                        state.supplementalVideoSetting(
                                            for: capture.id
                                        ).enabled
                                    },
                                    set: {
                                        state.setSupplementalVideoEnabled(
                                            captureID: capture.id,
                                            enabled: $0
                                        )
                                    }
                                )
                            )
                            .font(.caption)
                            .disabled(!editingEnabled)

                            HStack {
                                Text("Einblendung ab")
                                Spacer()
                                Text(
                                    timeLabel(
                                        setting.timelineStartSeconds
                                    )
                                )
                                .font(.caption2.monospacedDigit())
                            }
                            Slider(
                                value: Binding(
                                    get: {
                                        min(
                                            setting.timelineStartSeconds,
                                            outputDuration
                                        )
                                    },
                                    set: {
                                        state.setSupplementalVideoTimelineStart(
                                            captureID: capture.id,
                                            seconds: $0
                                        )
                                    }
                                ),
                                in: 0...outputDuration
                            )
                            .disabled(!editingEnabled || !setting.enabled)

                            HStack {
                                Text("Quelle ab")
                                Spacer()
                                Text(
                                    timeLabel(
                                        setting.sourceStartSeconds
                                    )
                                )
                                .font(.caption2.monospacedDigit())
                            }
                            Slider(
                                value: Binding(
                                    get: {
                                        min(
                                            setting.sourceStartSeconds,
                                            sourceDuration
                                        )
                                    },
                                    set: {
                                        state.setSupplementalVideoSourceStart(
                                            captureID: capture.id,
                                            seconds: $0
                                        )
                                    }
                                ),
                                in: 0...sourceDuration
                            )
                            .disabled(!editingEnabled || !setting.enabled)

                            HStack {
                                Text("Dauer")
                                Spacer()
                                Text(
                                    timeLabel(
                                        setting.durationSeconds
                                    )
                                )
                                .font(.caption2.monospacedDigit())
                            }
                            Slider(
                                value: Binding(
                                    get: {
                                        min(
                                            max(
                                                setting.durationSeconds,
                                                0.05
                                            ),
                                            max(sourceDuration, 0.05)
                                        )
                                    },
                                    set: {
                                        state.setSupplementalVideoDuration(
                                            captureID: capture.id,
                                            seconds: $0
                                        )
                                    }
                                ),
                                in: 0.05...max(sourceDuration, 0.05)
                            )
                            .disabled(!editingEnabled || !setting.enabled)

                            Text("Die Einblendung ersetzt nur das Bild im gewählten Zeitfenster; der Hauptton läuft weiter. Zu lange Bereiche werden beim Rendern automatisch an Quell- und Videolänge begrenzt.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }

                if state.asset != nil,
                   session.productionIntent(
                        for: project.id
                   )?.isLinkFirstClip != true {
                    Divider()
                    Button {
                        showOptionalCapture.toggle()
                    } label: {
                        Label(
                            showOptionalCapture
                                ? "Aufnahme ausblenden"
                                : "Eigene Aufnahme hinzufügen",
                            systemImage:
                                showOptionalCapture
                                ? "chevron.up"
                                : "video.badge.plus"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if showOptionalCapture {
                        CaptureCapabilityPanel { url, kind in
                            pendingURL = url
                            pendingCaptureKind = kind
                            if session.workspaceRightsAttestation?
                                .permitsUserDirectedProduction
                                == true {
                                importPendingMedia()
                            } else {
                                rightsConfirmed = false
                                showRightsSheet = true
                            }
                        }
                        .padding(.top, 8)
                    }

                    Text(
                        "Eigene Kamera-, Mikrofon- oder Bildschirmaufnahmen sind nur für selbst produzierte Projekte verfügbar."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if state.supplementalCaptures.isEmpty {
                    Text(
                        "Für diesen YouTube-Clip sind keine Kamera-, Mikrofon- oder Bildschirmrechte erforderlich."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func supplementalCaptureIcon(
        _ kind: CaptureKind
    ) -> String {
        switch kind {
        case .camera:
            return "video.fill"
        case .microphone:
            return "mic.fill"
        case .screen:
            return "rectangle.on.rectangle"
        case .systemAudio:
            return "waveform"
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
        case .userDeclaredResponsibility:
            return "Arbeitsbereich-Nutzererklärung"
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
                Text("Füge zuerst ein Video hinzu, um die Vorschau zu öffnen.")
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
            && session.activeProject?.isPaused != true
    }

    private func startProcessing(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        activeProcessingTask?.cancel()
        state.resumeProcessing()
        activeProcessingTask = Task { @MainActor in
            await operation()
            activeProcessingTask = nil
        }
    }

    private func stageTitle(_ stage: BlackstockStage) -> String {
        switch stage {
        case .production: return "Video hinzufügen"
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
            return "Schnitt, Format, Untertitel und Audio sind jetzt verfügbar."
        case .packaging:
            return "Bearbeitung ist eingefroren; Metadaten, Vorschaubild, Untertitel und Prüfung folgen."
        case .review:
            return "Prüfe die offenen Punkte, bevor du veröffentlichst."
        case .publishing:
            return "Externe Aktionen werden protokolliert und auf den Zielkanal begrenzt."
        case .published:
            return "Das veröffentlichte Video ist mit diesem Projekt verbunden."
        case .discovery, .research, .analysis:
            return "Dieses Projekt ist noch nicht bereit für den Editor."
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
