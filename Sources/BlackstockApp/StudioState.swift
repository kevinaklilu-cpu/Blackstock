#if os(macOS)
import Foundation
import AVFoundation
import AVKit
import BlackstockCore

@MainActor
final class StudioState: ObservableObject {
    @Published var asset: ProductionMediaAsset?
    @Published var player = AVPlayer()
    @Published var graph = EditGraph(createdAt: Date())
    @Published var ledger = ActivityLedger()
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 0
    @Published var lastUndoneRevisionID: UUID?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isRendering = false
    @Published var renderPreset: LocalRenderPreset = .hd1080
    @Published var renderArtifact: RenderArtifact?
    @Published var isTranscribing = false
    @Published var transcript: LocalTranscript?
    @Published var captionURL: URL?
    @Published var burnInCaptionsEnabled = false
    @Published var captionVisualStyle: CaptionVisualStyle = .clear
    @Published var speechAuthorizationState: LocalSpeechAuthorizationState = .notDetermined
    @Published var audioTechnicalAssessment: AudioTechnicalAssessment?
    @Published var audioSignalAssessment: AudioSignalAssessment?
    @Published var audioLoudnessAssessment: AudioLoudnessAssessment?
    @Published var reframeAspectRatio: ReframeAspectRatio = .landscape16x9
    @Published var reframeFocalX: Double = 0.5
    @Published var reframeFocalY: Double = 0.5
    @Published var isSuggestingFocalPoint = false
    @Published var focalPointProposal: VisionFocalPointProposal?
    @Published var transcriptStructure: TranscriptStructureSnapshot?
    @Published var retentionAdvisory: LocalRetentionAdvisory?
    @Published var retentionAdvisorAvailability: LocalRetentionAdvisorAvailability?
    @Published var isAnalyzingRetention = false
    @Published var storyboard: StoryboardPlan?
    @Published var supplementalCaptures: [SupplementalCaptureAsset] = []
    @Published var supplementalAudioMixSettings: [SupplementalAudioMixSetting] = []
    @Published var localClipCandidates: [LocalClipCandidate] = []
    @Published var savedClipSelections: [SavedClipSelection] = []
    @Published var isGeneratingClipCandidates = false
    @Published var clipCandidateStatusMessage: String?
    @Published var previewedLocalClipCandidateID: UUID?
    @Published var renderingSavedClipID: UUID?
    @Published var isRenderingSavedClipBatch = false
    @Published var isExportingSavedClipBatch = false
    @Published var packagingSuggestedTitle: String?
    @Published var overlayText = ""
    @Published var overlayStart: Double = 0
    @Published var overlayEnd: Double = 3
    @Published var overlayVerticalPosition: Double = 0.18

    var currentOutputDurationSeconds: Double {
        guard let asset else { return 0 }
        return EditTimelineResolver().resolve(
            sourceDurationSeconds: asset.durationSeconds,
            operations: graph.currentOperations
        ).outputDurationSeconds
    }

    private var clipCandidateSourceTranscript: LocalTranscript?
    private var correlationID = UUID()
    private var activeProjectID: UUID?
    private var workspaceStore: ProjectWorkspaceStore?

    func loadWorkspace(projectID: UUID) async {
        activeProjectID = projectID
        localClipCandidates = []
        clipCandidateStatusMessage = nil
        previewedLocalClipCandidateID = nil
        renderingSavedClipID = nil
        clipCandidateSourceTranscript = nil
        packagingSuggestedTitle = nil
        isGeneratingClipCandidates = false
        overlayText = ""
        overlayStart = 0
        overlayEnd = 3
        overlayVerticalPosition = 0.18

        do {
            let store = try makeWorkspaceStore()
            workspaceStore = store

            let loadResult = try store.loadWithRecovery(
                projectID: projectID
            )
            if let snapshot = loadResult.snapshot {
                asset = snapshot.mediaAsset
                graph = snapshot.editGraph
                ledger = snapshot.activityLedger
                if loadResult.recoveredFromBackup {
                    ledger.append(.init(
                        timestamp: Date(),
                        actor: .blackstock,
                        stage: .editing,
                        action: "workspace-recovered-from-backup",
                        summary: "Der primäre Projekt-Arbeitsbereich war nicht lesbar. Blackstock hat den letzten validierten lokalen Sicherungsstand geladen.",
                        reversible: false,
                        correlationID: correlationID
                    ))
                }
                if let sourceVersion = loadResult.migratedFromSchemaVersion {
                    ledger.append(.init(
                        timestamp: Date(),
                        actor: .blackstock,
                        stage: .editing,
                        action: "workspace-schema-migrated",
                        summary: "Projekt-Arbeitsbereich wurde lokal von Schema v\(sourceVersion) auf v\(WorkspaceSchema.current) migriert.",
                        reversible: false,
                        correlationID: correlationID
                    ))
                }
                storyboard = snapshot.storyboard
                trimStart = snapshot.trimStart
                trimEnd = snapshot.trimEnd
                transcript = snapshot.transcript
                captionURL = snapshot.captionURL
                burnInCaptionsEnabled =
                    snapshot.burnInCaptionsEnabled
                    ?? false
                captionVisualStyle =
                    snapshot.captionVisualStyle
                    ?? .clear
                if transcript == nil {
                    burnInCaptionsEnabled = false
                }
                renderArtifact = snapshot.renderArtifact
                supplementalCaptures = snapshot.supplementalCaptures ?? []
                supplementalAudioMixSettings =
                    snapshot.supplementalAudioMixSettings ?? []
                supplementalAudioMixSettings.removeAll { setting in
                    !supplementalCaptures.contains {
                        $0.id == setting.captureID
                    }
                }
                savedClipSelections =
                    (snapshot.savedClipSelections ?? [])
                    .map { selection in
                        guard let artifact =
                                selection.renderArtifact
                        else {
                            return selection
                        }
                        let exists =
                            FileManager.default
                            .fileExists(
                                atPath:
                                    artifact.fileURL.path
                            )
                        guard exists,
                              artifact
                                .hasCurrentTechnicalValidation
                        else {
                            return selection
                                .withRenderArtifact(nil)
                        }
                        return selection
                    }

                if let reframe = graph.currentOperations
                    .last(where: { $0.type == .reframe })?
                    .reframeSpec {
                    reframeAspectRatio = reframe.aspectRatio
                    reframeFocalX = reframe.focalX
                    reframeFocalY = reframe.focalY
                }

                if let transcript {
                    transcriptStructure = TranscriptStructureAnalyzer()
                        .analyze(transcript: transcript)
                    retentionAdvisorAvailability = LocalRetentionAdvisor()
                        .availability(
                            localeIdentifier: transcript.localeIdentifier
                        )
                }

                if let artifact = renderArtifact {
                    let fileExists = FileManager.default.fileExists(
                        atPath: artifact.fileURL.path
                    )
                    if !fileExists
                        || !artifact.hasCurrentTechnicalValidation {
                        renderArtifact = nil
                        persistWorkspaceIfPossible()
                        if fileExists {
                            errorMessage = "Der gespeicherte Render stammt aus einer älteren Validierungslogik und muss vor dem Veröffentlichungspaket neu gerendert werden."
                        }
                    }
                }

                if let asset {
                    if FileManager.default.fileExists(
                        atPath: asset.sourceURL.path
                    ) {
                        try await rebuildPreview()

                        let audioQCURL: URL
                        if let artifact = renderArtifact,
                           FileManager.default.fileExists(
                                atPath: artifact.fileURL.path
                           ) {
                            audioQCURL = artifact.fileURL
                        } else {
                            audioQCURL = asset.sourceURL
                        }
                        await refreshAudioInspection(
                            for: audioQCURL
                        )
                    } else {
                        errorMessage = "Das gespeicherte Produktionsmedium fehlt im Projekt-Arbeitsbereich."
                    }
                }
                if loadResult.recoveredFromBackup
                    || loadResult.migratedFromSchemaVersion != nil {
                    persistWorkspaceIfPossible()
                }
                if loadResult.recoveredFromBackup {
                    errorMessage = "Projekt-Arbeitsbereich wurde aus dem letzten validierten lokalen Sicherungsstand wiederhergestellt."
                } else if let sourceVersion = loadResult.migratedFromSchemaVersion {
                    errorMessage = "Projekt-Arbeitsbereich wurde sicher von Schema v\(sourceVersion) auf v\(WorkspaceSchema.current) migriert."
                }
                return
            }

            supplementalCaptures = []
            savedClipSelections = []
            burnInCaptionsEnabled = false
            captionVisualStyle = .clear
            loadStoryboard(projectID: projectID)
            persistWorkspaceIfPossible()
        } catch {
            errorMessage = "Projekt-Arbeitsbereich konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func loadStoryboard(projectID: UUID) {
        let key = "blackstock.storyboard.\(projectID.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let stored = try? decoder.decode(
                StoryboardPlan.self,
                from: data
            ) {
                storyboard = stored
                return
            }
        }

        storyboard = StoryboardPlan(
            projectID: projectID,
            updatedAt: Date()
        )
    }

    func addStoryboardBeat(
        projectID: UUID
    ) {
        if storyboard?.projectID != projectID {
            loadStoryboard(projectID: projectID)
        }
        guard var plan = storyboard else { return }

        let range: EditTimeRange?
        if trimEnd > trimStart {
            range = .init(
                startSeconds: trimStart,
                durationSeconds: trimEnd - trimStart
            )
        } else {
            range = nil
        }

        _ = plan.addBeat(
            title: "Beat \(plan.beats.count + 1)",
            timeRange: range,
            at: Date()
        )
        storyboard = plan
        persistStoryboard(plan)
        persistWorkspaceIfPossible()
    }

    func updateStoryboardBeat(
        id: UUID,
        title: String? = nil,
        purpose: String? = nil,
        visualDirection: String? = nil
    ) {
        guard var plan = storyboard else { return }
        guard plan.updateBeat(
            id: id,
            title: title,
            purpose: purpose,
            visualDirection: visualDirection,
            at: Date()
        ) else { return }

        storyboard = plan
        persistStoryboard(plan)
        persistWorkspaceIfPossible()
    }

    func removeStoryboardBeat(id: UUID) {
        guard var plan = storyboard else { return }
        guard plan.removeBeat(id: id, at: Date()) else { return }
        storyboard = plan
        persistStoryboard(plan)
        persistWorkspaceIfPossible()
    }

    func moveStoryboardBeat(
        from sourceIndex: Int,
        to destinationIndex: Int
    ) {
        guard var plan = storyboard else { return }
        guard plan.moveBeat(
            from: sourceIndex,
            to: destinationIndex,
            at: Date()
        ) else { return }
        storyboard = plan
        persistStoryboard(plan)
        persistWorkspaceIfPossible()
    }

    func importMovie(
        url: URL,
        projectID: UUID,
        authorization: ProductionMediaAuthorization,
        rightsEvidence: String,
        rightsConfirmed: Bool
    ) async {
        let evidence = rightsEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty else {
            errorMessage = "Hinterlege einen nachvollziehbaren Rechte- oder Eigentumsnachweis."
            return
        }
        guard rightsConfirmed else {
            errorMessage = "Bestätige zuerst, dass du die nötigen Rechte zur Verarbeitung und Veröffentlichung besitzt."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            activeProjectID = projectID
            let store = try workspaceStore ?? makeWorkspaceStore()
            workspaceStore = store

            let assetID = UUID()
            let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if didAccessSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let durableURL = try store.importMedia(
                sourceURL: url,
                projectID: projectID,
                assetID: assetID
            )
            let avAsset = AVURLAsset(url: durableURL)
            let duration = try await avAsset.load(.duration)
            let seconds = max(CMTimeGetSeconds(duration), 0)

            let imported = ProductionMediaAsset(
                id: assetID,
                displayName: url.lastPathComponent,
                sourceURL: durableURL,
                durationSeconds: seconds,
                authorization: authorization,
                rightsEvidence: [evidence],
                rightsAttestation: .init(
                    confirmedByUser: rightsConfirmed,
                    attestedAt: Date()
                ),
                importedAt: Date()
            )
            guard imported.mayEnterProduction else {
                errorMessage = "Dieses Medium ist für die Produktion nicht ausreichend autorisiert."
                return
            }

            asset = imported
            localClipCandidates = []
            savedClipSelections = []
            clipCandidateSourceTranscript = nil
            clipCandidateStatusMessage = nil
            previewedLocalClipCandidateID = nil
            graph = EditGraph(createdAt: Date())
            ledger = ActivityLedger()
            correlationID = UUID()
            trimStart = 0
            trimEnd = seconds
            lastUndoneRevisionID = nil
            renderArtifact = nil
            transcript = nil
            captionURL = nil
            burnInCaptionsEnabled = false
            captionVisualStyle = .clear
            transcriptStructure = nil
            retentionAdvisory = nil
            retentionAdvisorAvailability = nil
            audioTechnicalAssessment = nil
            audioSignalAssessment = nil
        audioLoudnessAssessment = nil
            focalPointProposal = nil
            reframeAspectRatio = .landscape16x9
            reframeFocalX = 0.5
            reframeFocalY = 0.5

            ledger.append(.init(
                timestamp: Date(),
                actor: .user,
                stage: .production,
                action: "media-imported",
                summary: "„\(imported.displayName)“ wurde mit Nutzer-Rechtebestätigung als Produktionsmedium hinzugefügt.",
                relatedSourceIDs: [imported.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))

            try await rebuildPreview()

            await refreshAudioInspection(
                for: imported.sourceURL
            )
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Video konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }

    func importSupplementalCapture(
        url: URL,
        kind: CaptureKind,
        projectID: UUID,
        rightsBasis: String,
        rightsEvidence: String,
        rightsConfirmed: Bool
    ) async -> Bool {
        let basis = rightsBasis.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let evidence = rightsEvidence.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !basis.isEmpty, !evidence.isEmpty else {
            errorMessage =
                "Hinterlege Nutzungsgrundlage und nachvollziehbaren Rechte-Nachweis."
            return false
        }
        guard rightsConfirmed else {
            errorMessage =
                "Bestätige zuerst die nötigen Nutzungs- und Veröffentlichungsrechte."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            activeProjectID = projectID
            let store = try workspaceStore ?? makeWorkspaceStore()
            workspaceStore = store

            let captureID = UUID()
            let durableURL = try store.importSupplementalCapture(
                sourceURL: url,
                projectID: projectID,
                assetID: captureID
            )

            let mimeType: String
            switch kind {
            case .microphone:
                mimeType = "audio/mp4"
            case .camera:
                mimeType = "video/quicktime"
            case .screen, .systemAudio:
                mimeType = "video/mp4"
            }

            let capture = SupplementalCaptureAsset(
                id: captureID,
                projectID: projectID,
                kind: kind,
                fileURL: durableURL,
                mimeType: mimeType,
                rightsBasis: basis,
                rightsEvidence: evidence,
                rightsConfirmed: rightsConfirmed,
                createdAt: Date()
            )

            guard capture.mayBeUsedInProduction else {
                try? FileManager.default.removeItem(at: durableURL)
                errorMessage =
                    "Die Aufnahme besitzt keine ausreichende Rechtefreigabe."
                return false
            }

            supplementalCaptures.removeAll {
                $0.id == capture.id
            }
            supplementalCaptures.append(capture)

            if !supplementalAudioMixSettings.contains(
                where: { $0.captureID == capture.id }
            ) {
                supplementalAudioMixSettings.append(
                    SupplementalAudioMixSetting(
                        captureID: capture.id
                    )
                )
            }

            ledger.append(.init(
                timestamp: Date(),
                actor: .user,
                stage: .production,
                action: "supplemental-capture-imported",
                summary: "„\(kind.germanTitle)“ wurde als zusätzliche lokale Aufnahme mit Rechtebestätigung im Projekt gespeichert.",
                relatedSourceIDs: [capture.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))

            persistWorkspaceIfPossible()
            errorMessage = nil
            return true
        } catch {
            errorMessage =
                "Zusätzliche Aufnahme konnte nicht gespeichert werden: "
                + error.localizedDescription
            return false
        }
    }

    func applyTrim() async {
        guard let asset else { return }
        let start = min(max(trimStart, 0), asset.durationSeconds)
        let end = min(max(trimEnd, start), asset.durationSeconds)
        guard end - start > 0.05 else {
            errorMessage = "Der gewählte Ausschnitt ist zu kurz."
            return
        }

        let before = graph.headID
        let operation = EditOperation(
            type: .trim,
            timeRange: .init(startSeconds: start, durationSeconds: end - start),
            createdAt: Date()
        )
        let revision = graph.apply(operation, actor: .user)
        lastUndoneRevisionID = nil
        renderArtifact = nil
        transcript = nil
        captionURL = nil
        burnInCaptionsEnabled = false
        audioTechnicalAssessment = nil
        audioSignalAssessment = nil
        audioLoudnessAssessment = nil
        transcriptStructure = nil
        retentionAdvisory = nil
        retentionAdvisorAvailability = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "trim-applied",
            summary: "Trim angewendet: \(format(start)) bis \(format(end)).",
            beforeRevisionID: before,
            afterRevisionID: revision.id,
            reversible: true,
            correlationID: correlationID
        ))

        do {
            try await rebuildPreview()
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func applyRemoveRange() async {
        guard let asset else { return }

        let start = min(max(trimStart, 0), asset.durationSeconds)
        let end = min(max(trimEnd, start), asset.durationSeconds)
        guard end - start > 0.05 else {
            errorMessage = "Der zu entfernende Bereich ist zu kurz."
            return
        }

        let operation = EditOperation(
            type: .removeRange,
            timeRange: .init(
                startSeconds: start,
                durationSeconds: end - start
            ),
            createdAt: Date()
        )
        let resolver = EditTimelineResolver()
        let currentPlan = resolver.resolve(
            sourceDurationSeconds: asset.durationSeconds,
            operations: graph.currentOperations
        )
        let nextPlan = resolver.resolve(
            sourceDurationSeconds: asset.durationSeconds,
            operations: graph.currentOperations + [operation]
        )
        guard nextPlan.hasContent else {
            errorMessage = "Die Auswahl würde den gesamten verbleibenden Inhalt entfernen."
            return
        }
        guard nextPlan.outputDurationSeconds
                < currentPlan.outputDurationSeconds - 0.001 else {
            errorMessage = "Die Auswahl liegt außerhalb des aktuellen Schnitts oder wurde bereits entfernt."
            return
        }

        let before = graph.headID
        let revision = graph.apply(operation, actor: .user)
        lastUndoneRevisionID = nil
        renderArtifact = nil
        transcript = nil
        captionURL = nil
        burnInCaptionsEnabled = false
        audioTechnicalAssessment = nil
        audioSignalAssessment = nil
        audioLoudnessAssessment = nil
        transcriptStructure = nil
        retentionAdvisory = nil
        retentionAdvisorAvailability = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "range-removed",
            summary: "Bereich entfernt: \(format(start)) bis \(format(end)).",
            beforeRevisionID: before,
            afterRevisionID: revision.id,
            reversible: true,
            correlationID: correlationID
        ))

        do {
            try await rebuildPreview()
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Schnitt-Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func undo() async {
        let undone = graph.headID
        guard let restored = graph.undo() else { return }
        lastUndoneRevisionID = undone
        renderArtifact = nil
        transcript = nil
        captionURL = nil
        burnInCaptionsEnabled = false
        audioTechnicalAssessment = nil
        audioSignalAssessment = nil
        audioLoudnessAssessment = nil
        transcriptStructure = nil
        retentionAdvisory = nil
        retentionAdvisorAvailability = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "undo",
            summary: "Letzte Änderung wurde rückgängig gemacht.",
            beforeRevisionID: undone,
            afterRevisionID: restored.id,
            reversible: true,
            correlationID: correlationID
        ))

        await refreshPreviewAfterHistoryChange()
        persistWorkspaceIfPossible()
    }

    func redo() async {
        guard let id = lastUndoneRevisionID,
              let restored = graph.redo(to: id) else { return }
        lastUndoneRevisionID = nil
        renderArtifact = nil
        transcript = nil
        captionURL = nil
        burnInCaptionsEnabled = false
        audioTechnicalAssessment = nil
        audioSignalAssessment = nil
        audioLoudnessAssessment = nil
        transcriptStructure = nil
        retentionAdvisory = nil
        retentionAdvisorAvailability = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "redo",
            summary: "Rückgängig gemachte Änderung wurde wiederhergestellt.",
            afterRevisionID: restored.id,
            reversible: true,
            correlationID: correlationID
        ))

        await refreshPreviewAfterHistoryChange()
        persistWorkspaceIfPossible()
    }

    func suggestFocalPoint() async {
        guard let asset else {
            errorMessage = "Kein Produktionsmedium geladen."
            return
        }

        isSuggestingFocalPoint = true
        defer { isSuggestingFocalPoint = false }

        do {
            let proposal = try await LocalVisionFocalPointSuggester()
                .suggest(url: asset.sourceURL)
            focalPointProposal = proposal
            reframeFocalX = proposal.focalX
            reframeFocalY = proposal.focalY

            ledger.append(.init(
                timestamp: Date(),
                actor: .blackstock,
                stage: .editing,
                action: "reframe-focus-proposed",
                summary: "\(proposal.explanation) Der Vorschlag wurde nur in die Regler übernommen und noch nicht angewendet.",
                relatedSourceIDs: [asset.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch LocalVisionFocalPointError.noRelevantObservation {
            focalPointProposal = nil
            errorMessage = "Vision hat in den Stichproben kein Gesicht oder keine Person erkannt. Der Fokus bleibt vollständig manuell."
        } catch {
            focalPointProposal = nil
            errorMessage = "Lokaler Fokusvorschlag fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func applyTextOverlay() async {
        guard let asset else {
            errorMessage = "Kein Produktionsmedium geladen."
            return
        }

        let text = overlayText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else {
            errorMessage = "Text-Overlay benötigt sichtbaren Text."
            return
        }

        let timeline = EditTimelineResolver().resolve(
            sourceDurationSeconds: asset.durationSeconds,
            operations: graph.currentOperations
        )
        guard timeline.hasContent else {
            errorMessage = "Der aktuelle Schnitt enthält keinen Bereich für ein Text-Overlay."
            return
        }

        let start = min(
            max(overlayStart, 0),
            timeline.outputDurationSeconds
        )
        let end = min(
            max(overlayEnd, start),
            timeline.outputDurationSeconds
        )
        guard end - start >= 0.05 else {
            errorMessage = "Das Text-Overlay benötigt ein sichtbares Zeitfenster."
            return
        }

        let before = graph.headID
        let operation = EditOperation(
            type: .overlay,
            timeRange: .init(
                startSeconds: start,
                durationSeconds: end - start
            ),
            value: min(
                max(overlayVerticalPosition, 0.05),
                0.95
            ),
            text: text,
            createdAt: Date()
        )
        let revision = graph.apply(
            operation,
            actor: .user
        )
        lastUndoneRevisionID = nil
        renderArtifact = nil
        invalidateSavedClipRenders()

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "text-overlay-applied",
            summary:
                "Text-Overlay „\(text)“ von \(format(start)) bis \(format(end)) angewendet.",
            beforeRevisionID: before,
            afterRevisionID: revision.id,
            reversible: true,
            correlationID: correlationID
        ))

        overlayText = ""
        persistWorkspaceIfPossible()
        errorMessage = nil
    }

    func prepareOutputPreset(
        _ preset: CreatorOutputPreset
    ) {
        reframeAspectRatio = preset.aspectRatio
        captionVisualStyle = preset.captionStyle

        if transcript != nil {
            burnInCaptionsEnabled =
                preset.prefersVisibleCaptions
        }

        renderArtifact = nil
        invalidateSavedClipRenders()
        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "output-preset-prepared",
            summary:
                transcript == nil
                ? "Ausgabe-Preset „\(preset.germanTitle)“ vorbereitet. Sichtbare Untertitel bleiben aus, bis ein lokales Transkript vorhanden ist."
                : "Ausgabe-Preset „\(preset.germanTitle)“ vorbereitet. Format und Untertiteloptionen wurden vorpositioniert; die Formatänderung ist noch nicht angewendet.",
            reversible: false,
            correlationID: correlationID
        ))
        persistWorkspaceIfPossible()
        errorMessage = nil
    }

    func prepareShortFormSetup() {
        prepareOutputPreset(.shortVertical)
    }

    func applyReframe() async {
        guard asset != nil else { return }

        let before = graph.headID
        let spec = ReframeSpec(
            aspectRatio: reframeAspectRatio,
            focalX: reframeFocalX,
            focalY: reframeFocalY
        )
        let operation = EditOperation(
            type: .reframe,
            reframeSpec: spec,
            createdAt: Date()
        )
        let revision = graph.apply(operation, actor: .user)
        lastUndoneRevisionID = nil
        renderArtifact = nil
        invalidateSavedClipRenders()
        audioTechnicalAssessment = nil
        audioSignalAssessment = nil
        audioLoudnessAssessment = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "reframe-applied",
            summary: "Reframe auf \(spec.aspectRatio.rawValue) mit manuellem Fokuspunkt angewendet.",
            beforeRevisionID: before,
            afterRevisionID: revision.id,
            reversible: true,
            correlationID: correlationID
        ))

        do {
            try await rebuildPreview()
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Reframe-Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func generateLocalClipCandidates(
        localeIdentifier: String
    ) async {
        guard let asset else {
            clipCandidateStatusMessage =
                "Kein autorisiertes Produktionsmedium geladen."
            return
        }

        isGeneratingClipCandidates = true
        clipCandidateStatusMessage = nil
        defer { isGeneratingClipCandidates = false }

        let transcriber = LocalOnDeviceTranscriber()
        var authorization = transcriber.authorizationState()
        if authorization == .notDetermined {
            authorization = await transcriber.requestAuthorization()
        }
        speechAuthorizationState = authorization

        guard authorization == .authorized else {
            localClipCandidates = []
            clipCandidateStatusMessage =
                authorization == .restricted
                ? "Lokale Spracherkennung ist auf diesem Mac eingeschränkt."
                : "Lokale Spracherkennung wurde nicht erlaubt."
            return
        }

        guard transcriber.isOnDeviceAvailable(
            localeIdentifier: localeIdentifier
        ) else {
            localClipCandidates = []
            clipCandidateStatusMessage =
                "Für diese Sprache ist auf diesem Mac keine On-Device-Spracherkennung verfügbar. Blackstock verwendet keinen Cloud-Fallback."
            return
        }

        do {
            let sourceTranscript =
                try await transcriber.transcribeVideo(
                    url: asset.sourceURL,
                    localeIdentifier: localeIdentifier
                )

            clipCandidateSourceTranscript =
                sourceTranscript

            let candidates = LocalClipCandidateGenerator()
                .generate(
                    transcript: sourceTranscript,
                    sourceDurationSeconds:
                        asset.durationSeconds
                )

            localClipCandidates = candidates
            if candidates.isEmpty {
                clipCandidateStatusMessage =
                    "Keine mindestens 15 Sekunden langen zusammenhängenden Sprachblöcke gefunden. Blackstock erfindet deshalb keine Clip-Vorschläge."
            } else {
                clipCandidateStatusMessage =
                    "\(candidates.count) lokale Clip-Kandidaten aus Sprachsegmenten und gemessenen Pausen gefunden."
            }

            ledger.append(.init(
                timestamp: Date(),
                actor: .blackstock,
                stage: .editing,
                action:
                    "local-clip-candidates-generated",
                summary:
                    "\(candidates.count) lokale Clip-Kandidaten wurden deterministisch aus dem Original-Transkript und gemessenen Pausen abgeleitet; es wurde keine Erfolgs- oder Viralitätsnote erzeugt.",
                relatedSourceIDs:
                    candidates.flatMap(\.segmentIDs)
                        .map(\.uuidString),
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            localClipCandidates = []
            clipCandidateStatusMessage =
                "Lokale Clip-Analyse fehlgeschlagen: "
                + error.localizedDescription
        }
    }

    func saveLocalClipCandidate(
        _ candidate: LocalClipCandidate
    ) {
        let duplicate = savedClipSelections.contains {
            abs(
                $0.sourceRange.startSeconds
                - candidate.sourceRange.startSeconds
            ) < 0.05
            && abs(
                $0.sourceRange.durationSeconds
                - candidate.sourceRange.durationSeconds
            ) < 0.05
        }
        guard !duplicate else {
            clipCandidateStatusMessage =
                "Dieser Clip-Kandidat ist bereits in deiner Clip-Liste."
            return
        }

        let saved = SavedClipSelection(
            candidate: candidate,
            transcript:
                clipTranscript(
                    for: candidate
                )
        )
        savedClipSelections.append(saved)
        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "clip-selection-saved",
            summary:
                "Clip-Auswahl gespeichert: \(format(saved.sourceRange.startSeconds)) bis \(format(saved.sourceRange.endSeconds)).",
            relatedSourceIDs: [saved.id.uuidString],
            reversible: false,
            correlationID: correlationID
        ))
        persistWorkspaceIfPossible()
        clipCandidateStatusMessage =
            "Clip-Kandidat wurde in der projektgebundenen Clip-Liste gespeichert."
        errorMessage = nil
    }

    func renameSavedClipSelection(
        id: UUID,
        title: String
    ) {
        guard let index =
                savedClipSelections.firstIndex(
                    where: { $0.id == id }
                ) else {
            return
        }

        savedClipSelections[index] =
            savedClipSelections[index]
                .withTitle(title)
        persistWorkspaceIfPossible()
        clipCandidateStatusMessage =
            "Clip-Name wurde gespeichert."
        errorMessage = nil
    }

    func removeSavedClipSelection(
        _ selection: SavedClipSelection
    ) {
        if let artifact = selection.renderArtifact {
            try? FileManager.default.removeItem(
                at: artifact.fileURL
            )
        }
        savedClipSelections.removeAll {
            $0.id == selection.id
        }
        persistWorkspaceIfPossible()
        clipCandidateStatusMessage =
            "Gespeicherte Clip-Auswahl entfernt."
        errorMessage = nil
    }

    func loadSavedClipSelection(
        _ selection: SavedClipSelection
    ) {
        guard let asset else {
            errorMessage =
                "Kein Produktionsmedium geladen."
            return
        }

        let start = min(
            max(selection.sourceRange.startSeconds, 0),
            asset.durationSeconds
        )
        let end = min(
            max(selection.sourceRange.endSeconds, start),
            asset.durationSeconds
        )
        guard end - start > 0.05 else {
            errorMessage =
                "Die gespeicherte Clip-Auswahl ist nicht mehr gültig."
            return
        }

        trimStart = start
        trimEnd = end
        clipCandidateStatusMessage =
            "Gespeicherte Clip-Auswahl in die Timeline geladen. Erst „Als Trim setzen“ verändert den EditGraph."
        errorMessage = nil
    }

    func exportRenderedSavedClips(
        to directoryURL: URL
    ) {
        guard !isExportingSavedClipBatch else {
            return
        }

        let readySelections = savedClipSelections.filter {
            guard let artifact = $0.renderArtifact else {
                return false
            }
            return artifact.hasCurrentTechnicalValidation
                && FileManager.default.fileExists(
                    atPath: artifact.fileURL.path
                )
        }
        guard !readySelections.isEmpty else {
            clipCandidateStatusMessage =
                "Erstelle zuerst mindestens eine validierte Clip-Datei."
            return
        }

        isExportingSavedClipBatch = true
        defer {
            isExportingSavedClipBatch = false
        }

        let accessed =
            directoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        struct ExportedClipRecord: Codable {
            let clipID: UUID
            let title: String?
            let sourceStartSeconds: Double
            let sourceDurationSeconds: Double
            let mp4FileName: String
            let captionFileName: String?
            let renderSHA256: String
        }

        struct ExportManifest: Codable {
            let schemaVersion: Int
            let projectID: UUID
            let exportedAt: Date
            let clips: [ExportedClipRecord]
        }

        do {
            var records: [ExportedClipRecord] = []
            let fileManager = FileManager.default

            for (index, selection) in
                readySelections.enumerated() {
                guard let artifact =
                        selection.renderArtifact else {
                    continue
                }

                let titleComponent =
                    safeExportNameComponent(
                        selection.displayTitle
                    )
                let baseName =
                    String(
                        format:
                            "Blackstock-Clip-%02d",
                        index + 1
                    )
                    + (
                        titleComponent.isEmpty
                        || titleComponent == "Clip"
                        ? ""
                        : "-" + titleComponent
                    )
                let mp4URL = try availableExportURL(
                    in: directoryURL,
                    baseName: baseName,
                    pathExtension: "mp4"
                )
                try fileManager.copyItem(
                    at: artifact.fileURL,
                    to: mp4URL
                )

                var captionFileName: String?
                if let transcript =
                    selection.transcript {
                    let captionURL =
                        try availableExportURL(
                            in: directoryURL,
                            baseName: baseName,
                            pathExtension: "vtt"
                        )
                    try WebVTTCaptionWriter().write(
                        transcript: transcript,
                        to: captionURL
                    )
                    captionFileName =
                        captionURL.lastPathComponent
                }

                records.append(
                    ExportedClipRecord(
                        clipID: selection.id,
                        title: selection.title,
                        sourceStartSeconds:
                            selection.sourceRange
                                .startSeconds,
                        sourceDurationSeconds:
                            selection.sourceRange
                                .durationSeconds,
                        mp4FileName:
                            mp4URL.lastPathComponent,
                        captionFileName:
                            captionFileName,
                        renderSHA256: artifact.sha256
                    )
                )
            }

            guard let projectID =
                    activeProjectID else {
                throw CocoaError(.fileNoSuchFile)
            }

            let manifest = ExportManifest(
                schemaVersion: 1,
                projectID: projectID,
                exportedAt: Date(),
                clips: records
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData =
                try encoder.encode(manifest)
            let manifestURL =
                try availableExportURL(
                    in: directoryURL,
                    baseName:
                        "Blackstock-Clips",
                    pathExtension: "json"
                )
            try manifestData.write(
                to: manifestURL,
                options: .atomic
            )

            ledger.append(.init(
                timestamp: Date(),
                actor: .user,
                stage: .editing,
                action:
                    "saved-clips-exported",
                summary:
                    "\(records.count) gerenderte Clips wurden mit nachvollziehbarem Export-Manifest in einen vom Nutzer gewählten Ordner kopiert.",
                relatedSourceIDs:
                    records.map {
                        $0.clipID.uuidString
                    },
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            clipCandidateStatusMessage =
                "\(records.count) Clip-Dateien wurden exportiert. Vorhandene Clip-Transkripte liegen zusätzlich als WebVTT im Zielordner."
            errorMessage = nil
        } catch {
            errorMessage =
                "Clip-Export fehlgeschlagen: "
                + error.localizedDescription
        }
    }

    private func safeExportNameComponent(
        _ value: String
    ) -> String {
        let allowed =
            CharacterSet.alphanumerics
            .union(
                CharacterSet(
                    charactersIn: "-_ "
                )
            )
        let characters = value.map { character in
            character.unicodeScalars.allSatisfy {
                allowed.contains($0)
            }
            ? character
            : Character("-")
        }
        let normalized = String(characters)
            .replacingOccurrences(
                of: " ",
                with: "-"
            )
            .split(
                separator: "-",
                omittingEmptySubsequences: true
            )
            .joined(separator: "-")
        return String(
            normalized.prefix(64)
        )
    }

    private func availableExportURL(
        in directoryURL: URL,
        baseName: String,
        pathExtension: String
    ) throws -> URL {
        let fileManager = FileManager.default
        var candidate =
            directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(
                pathExtension
            )
        var suffix = 2

        while fileManager.fileExists(
            atPath: candidate.path
        ) {
            candidate =
                directoryURL
                .appendingPathComponent(
                    baseName
                    + "-"
                    + String(suffix)
                )
                .appendingPathExtension(
                    pathExtension
                )
            suffix += 1
        }
        return candidate
    }

    func renderAllSavedClipSelections() async {
        guard !savedClipSelections.isEmpty else {
            clipCandidateStatusMessage =
                "Es sind noch keine gespeicherten Clips vorhanden."
            return
        }
        guard !isRenderingSavedClipBatch,
              renderingSavedClipID == nil else {
            errorMessage =
                "Es läuft bereits ein Clip-Render."
            return
        }

        isRenderingSavedClipBatch = true
        defer {
            isRenderingSavedClipBatch = false
        }

        let ids = savedClipSelections.map(\.id)
        var completed = 0

        for id in ids {
            guard let selection =
                    savedClipSelections.first(
                        where: { $0.id == id }
                    ) else {
                continue
            }

            await renderSavedClipSelection(
                selection
            )
            if errorMessage != nil {
                clipCandidateStatusMessage =
                    "Stapel-Render nach \(completed) fertigen Clip-Dateien gestoppt."
                return
            }
            completed += 1
        }

        clipCandidateStatusMessage =
            "\(completed) gespeicherte Clips wurden als eigene validierte MP4-Dateien erstellt."
        errorMessage = nil
    }

    func renderSavedClipSelection(
        _ selection: SavedClipSelection
    ) async {
        guard let asset,
              let projectID = activeProjectID else {
            errorMessage =
                "Kein Produktionsmedium oder Projekt geladen."
            return
        }
        guard renderingSavedClipID == nil else {
            errorMessage =
                "Es wird bereits ein gespeicherter Clip gerendert."
            return
        }

        renderingSavedClipID = selection.id
        defer { renderingSavedClipID = nil }

        do {
            var clipGraph = EditGraph(
                createdAt: Date()
            )
            _ = clipGraph.apply(
                EditOperation(
                    type: .trim,
                    timeRange: selection.sourceRange,
                    createdAt: Date()
                ),
                actor: .user
            )

            if let reframe = graph.currentOperations
                .last(
                    where: {
                        $0.type == .reframe
                    }
                )?
                .reframeSpec {
                _ = clipGraph.apply(
                    EditOperation(
                        type: .reframe,
                        reframeSpec: reframe,
                        createdAt: Date()
                    ),
                    actor: .user
                )
            }

            let store =
                try workspaceStore
                ?? makeWorkspaceStore()
            workspaceStore = store
            let clipsDirectory =
                try store.renderDirectory(
                    projectID: projectID
                )
                .appendingPathComponent(
                    "Clips",
                    isDirectory: true
                )
            try FileManager.default
                .createDirectory(
                    at: clipsDirectory,
                    withIntermediateDirectories:
                        true
                )
            let outputURL =
                clipsDirectory
                .appendingPathComponent(
                    selection.id.uuidString
                )
                .appendingPathExtension("mp4")

            let artifact =
                try await LocalVideoRenderer()
                .render(
                    projectID: projectID,
                    asset: asset,
                    graph: clipGraph,
                    outputURL: outputURL,
                    preset: renderPreset,
                    transcript:
                        selection.transcript,
                    burnInCaptions:
                        burnInCaptionsEnabled
                        && selection.transcript
                            != nil,
                    captionStyle:
                        captionVisualStyle
                )

            guard let index =
                savedClipSelections
                .firstIndex(
                    where: {
                        $0.id == selection.id
                    }
                ) else {
                throw CocoaError(
                    .fileNoSuchFile
                )
            }
            savedClipSelections[index] =
                savedClipSelections[index]
                .withRenderArtifact(
                    artifact
                )

            ledger.append(.init(
                timestamp: Date(),
                actor: .blackstock,
                stage: .editing,
                action:
                    "saved-clip-render-created",
                summary:
                    "Gespeicherter Clip wurde als eigene validierte MP4-Datei gerendert.",
                relatedSourceIDs: [
                    selection.id.uuidString,
                    artifact.id.uuidString
                ],
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            clipCandidateStatusMessage =
                "Clip-Datei ist fertig und projektbezogen gespeichert."
            errorMessage = nil
        } catch {
            errorMessage =
                "Gespeicherter Clip konnte nicht gerendert werden: "
                + error.localizedDescription
        }
    }

    func useSavedClipForPackaging(
        _ selection: SavedClipSelection
    ) async {
        guard let artifact =
                selection.renderArtifact,
              artifact.hasCurrentTechnicalValidation,
              FileManager.default.fileExists(
                atPath: artifact.fileURL.path
              ) else {
            errorMessage =
                "Dieser Clip besitzt noch keine aktuelle validierte Render-Datei."
            return
        }

        await applySavedClipSelection(
            selection
        )
        guard errorMessage == nil else {
            return
        }

        renderArtifact = artifact
        packagingSuggestedTitle =
            selection.title
        await refreshAudioInspection(
            for: artifact.fileURL
        )

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action:
                "saved-clip-selected-for-packaging",
            summary:
                "Ein gespeicherter, technisch validierter Clip wurde als aktueller Kandidat für Packaging und Review ausgewählt.",
            relatedSourceIDs: [
                selection.id.uuidString,
                artifact.id.uuidString
            ],
            reversible: false,
            correlationID: correlationID
        ))
        persistWorkspaceIfPossible()
        clipCandidateStatusMessage =
            "Dieser Clip ist jetzt der aktuelle Packaging-Kandidat. Nutze „Veröffentlichungspaket & Prüfung“, um fortzufahren."
        errorMessage = nil
    }

    func previewSavedClipSelection(
        _ selection: SavedClipSelection
    ) async {
        let candidate = LocalClipCandidate(
            id: selection.id,
            sourceRange: selection.sourceRange,
            transcriptPreview:
                selection.transcriptPreview,
            wordCount: selection.wordCount,
            averageConfidence: nil,
            segmentIDs: []
        )
        await previewLocalClipCandidate(candidate)
    }

    func applySavedClipSelection(
        _ selection: SavedClipSelection
    ) async {
        let candidate = LocalClipCandidate(
            id: selection.id,
            sourceRange: selection.sourceRange,
            transcriptPreview:
                selection.transcriptPreview,
            wordCount: selection.wordCount,
            averageConfidence: nil,
            segmentIDs: []
        )
        await applyLocalClipCandidate(candidate)
        guard errorMessage == nil,
              let clipTranscript =
                selection.transcript else {
            return
        }

        transcript = clipTranscript
        transcriptStructure =
            TranscriptStructureAnalyzer()
            .analyze(
                transcript: clipTranscript
            )
        retentionAdvisorAvailability =
            LocalRetentionAdvisor()
            .availability(
                localeIdentifier:
                    clipTranscript
                        .localeIdentifier
            )

        if let projectID = activeProjectID {
            do {
                let store =
                    try workspaceStore
                    ?? makeWorkspaceStore()
                workspaceStore = store
                let directory =
                    try store.captionDirectory(
                        projectID: projectID
                    )
                let outputURL =
                    directory
                    .appendingPathComponent(
                        "clip-"
                        + selection.id
                            .uuidString
                    )
                    .appendingPathExtension(
                        "vtt"
                    )
                try WebVTTCaptionWriter()
                    .write(
                        transcript:
                            clipTranscript,
                        to: outputURL
                    )
                captionURL = outputURL
            } catch {
                errorMessage =
                    "Clip wurde übernommen, aber die lokale Untertiteldatei konnte nicht gespeichert werden: "
                    + error.localizedDescription
                persistWorkspaceIfPossible()
                return
            }
        }

        persistWorkspaceIfPossible()
        clipCandidateStatusMessage =
            "Gespeicherter Clip wurde übernommen; sein lokales Transkript steht direkt für Untertitel und weitere Analyse bereit."
        errorMessage = nil
    }

    func previewLocalClipCandidate(
        _ candidate: LocalClipCandidate
    ) async {
        guard let asset else {
            errorMessage =
                "Kein Produktionsmedium geladen."
            return
        }

        let start = min(
            max(candidate.sourceRange.startSeconds, 0),
            asset.durationSeconds
        )
        let end = min(
            max(candidate.sourceRange.endSeconds, start),
            asset.durationSeconds
        )
        guard end - start > 0.05 else {
            errorMessage =
                "Der vorgeschlagene Clip-Bereich ist nicht mehr gültig."
            return
        }

        do {
            let source = AVURLAsset(
                url: asset.sourceURL
            )
            let composition = AVMutableComposition()
            let range = CMTimeRange(
                start: CMTime(
                    seconds: start,
                    preferredTimescale: 600
                ),
                duration: CMTime(
                    seconds: end - start,
                    preferredTimescale: 600
                )
            )
            try await composition.insertTimeRange(
                range,
                of: source,
                at: .zero
            )

            player.pause()
            player.replaceCurrentItem(
                with: AVPlayerItem(
                    asset: composition
                )
            )
            await player.seek(to: .zero)
            player.play()
            previewedLocalClipCandidateID =
                candidate.id
            clipCandidateStatusMessage =
                "Kandidaten-Vorschau läuft im Hauptplayer. Der EditGraph wurde nicht verändert."
            errorMessage = nil
        } catch {
            previewedLocalClipCandidateID = nil
            errorMessage =
                "Clip-Kandidat konnte nicht vorgespielt werden: "
                + error.localizedDescription
        }
    }

    func restoreEditedPreview() async {
        do {
            player.pause()
            try await rebuildPreview()
            previewedLocalClipCandidateID = nil
            clipCandidateStatusMessage =
                "Aktuelle Schnittvorschau wiederhergestellt."
            errorMessage = nil
        } catch {
            errorMessage =
                "Schnittvorschau konnte nicht wiederhergestellt werden: "
                + error.localizedDescription
        }
    }

    func applyLocalClipCandidate(
        _ candidate: LocalClipCandidate
    ) async {
        guard let asset else {
            errorMessage =
                "Kein Produktionsmedium geladen."
            return
        }

        let start = min(
            max(candidate.sourceRange.startSeconds, 0),
            asset.durationSeconds
        )
        let end = min(
            max(candidate.sourceRange.endSeconds, start),
            asset.durationSeconds
        )
        guard end - start > 0.05 else {
            errorMessage =
                "Der vorgeschlagene Clip-Bereich ist nicht mehr gültig."
            return
        }

        let before = graph.headID
        let operation = EditOperation(
            type: .trim,
            timeRange: .init(
                startSeconds: start,
                durationSeconds: end - start
            ),
            createdAt: Date()
        )
        let revision = graph.apply(
            operation,
            actor: .user
        )

        trimStart = start
        trimEnd = end
        previewedLocalClipCandidateID = nil
        lastUndoneRevisionID = nil
        renderArtifact = nil
        transcript = nil
        captionURL = nil
        burnInCaptionsEnabled = false
        transcriptStructure = nil
        retentionAdvisory = nil
        retentionAdvisorAvailability = nil
        audioTechnicalAssessment = nil
        audioSignalAssessment = nil
        audioLoudnessAssessment = nil

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action:
                "local-clip-candidate-applied",
            summary:
                "Lokaler Clip-Kandidat als non-destruktiver Trim übernommen: \(format(start)) bis \(format(end)).",
            relatedSourceIDs:
                candidate.segmentIDs
                    .map(\.uuidString),
            beforeRevisionID: before,
            afterRevisionID: revision.id,
            reversible: true,
            correlationID: correlationID
        ))

        do {
            try await rebuildPreview()
            persistWorkspaceIfPossible()
            clipCandidateStatusMessage =
                "Clip-Kandidat wurde als EditGraph-Revision übernommen und kann rückgängig gemacht werden."
            errorMessage = nil
        } catch {
            errorMessage =
                "Clip-Vorschau konnte nicht aktualisiert werden: "
                + error.localizedDescription
        }
    }

    func generateLocalCaptions(
        localeIdentifier: String
    ) async {
        guard let asset else {
            errorMessage = "Kein Produktionsmedium geladen."
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let transcriber = LocalOnDeviceTranscriber()
        var authorization = transcriber.authorizationState()
        if authorization == .notDetermined {
            authorization = await transcriber.requestAuthorization()
        }
        speechAuthorizationState = authorization

        guard authorization == .authorized else {
            errorMessage = authorization == .restricted
                ? "Spracherkennung ist auf diesem Mac eingeschränkt."
                : "Spracherkennung wurde nicht erlaubt."
            return
        }

        guard transcriber.isOnDeviceAvailable(
            localeIdentifier: localeIdentifier
        ) else {
            errorMessage = "Für diese Sprache ist auf diesem Mac keine On-Device-Spracherkennung verfügbar. Blackstock verwendet keinen stillen Cloud-Fallback."
            return
        }

        do {
            let timeline = EditTimelineResolver().resolve(
                sourceDurationSeconds: asset.durationSeconds,
                operations: graph.currentOperations
            )
            guard timeline.hasContent else {
                errorMessage = "Der aktuelle Schnitt enthält keinen transkribierbaren Inhalt."
                return
            }

            let editedAudioURL = try await EditedTimelineAudioMaterializer()
                .materialize(
                    sourceURL: asset.sourceURL,
                    sourceRanges: timeline.sourceRanges
                )
            defer {
                try? FileManager.default.removeItem(at: editedAudioURL)
            }

            let localTranscript = try await transcriber.transcribeVideo(
                url: editedAudioURL,
                localeIdentifier: localeIdentifier
            )

            guard let projectID = activeProjectID else {
                throw CocoaError(.fileNoSuchFile)
            }
            let store = try workspaceStore ?? makeWorkspaceStore()
            workspaceStore = store
            let directory = try store.captionDirectory(
                projectID: projectID
            )
            let outputURL = directory
                .appendingPathComponent(asset.id.uuidString)
                .appendingPathExtension("vtt")
            try WebVTTCaptionWriter().write(
                transcript: localTranscript,
                to: outputURL
            )

            transcript = localTranscript
            captionURL = outputURL
            if burnInCaptionsEnabled {
                renderArtifact = nil
            }
            let structure = TranscriptStructureAnalyzer().analyze(
                transcript: localTranscript
            )
            transcriptStructure = structure
            retentionAdvisory = nil
            retentionAdvisorAvailability = LocalRetentionAdvisor().availability(
                localeIdentifier: localTranscript.localeIdentifier
            )

            ledger.append(.init(
                timestamp: Date(),
                actor: .blackstock,
                stage: .editing,
                action: "local-captions-generated",
                summary: "Lokales Transkript und WebVTT-Untertitel wurden lokal erzeugt.",
                relatedSourceIDs: [asset.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Lokale Transkription fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func invalidateSavedClipRenders() {
        var changed = false
        savedClipSelections = savedClipSelections.map {
            guard let artifact =
                    $0.renderArtifact else {
                return $0
            }
            try? FileManager.default
                .removeItem(
                    at: artifact.fileURL
                )
            changed = true
            return $0.withRenderArtifact(nil)
        }
        if changed {
            persistWorkspaceIfPossible()
        }
    }

    func setBurnInCaptionsEnabled(
        _ enabled: Bool
    ) {
        guard enabled == false || transcript != nil else {
            errorMessage =
                "Erstelle zuerst lokale Untertitel, bevor du Burn-in-Captions aktivierst."
            return
        }
        guard burnInCaptionsEnabled != enabled else {
            return
        }

        burnInCaptionsEnabled = enabled
        renderArtifact = nil
        invalidateSavedClipRenders()

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: enabled
                ? "caption-burn-in-enabled"
                : "caption-burn-in-disabled",
            summary: enabled
                ? "Sichtbare Burn-in-Captions wurden für den nächsten lokalen Render aktiviert."
                : "Sichtbare Burn-in-Captions wurden für den nächsten lokalen Render deaktiviert.",
            reversible: false,
            correlationID: correlationID
        ))

        persistWorkspaceIfPossible()
        errorMessage = nil
    }

    func setCaptionVisualStyle(
        _ style: CaptionVisualStyle
    ) {
        guard captionVisualStyle != style else {
            return
        }

        captionVisualStyle = style
        if burnInCaptionsEnabled {
            renderArtifact = nil
        }
        invalidateSavedClipRenders()

        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "caption-visual-style-changed",
            summary:
                "Untertitelstil auf „\(style.germanTitle)“ geändert.",
            reversible: false,
            correlationID: correlationID
        ))

        persistWorkspaceIfPossible()
        errorMessage = nil
    }

    func analyzeRetentionLocally() async {
        guard let transcript,
              let transcriptStructure else {
            errorMessage = "Erstelle zuerst ein lokales Transkript."
            return
        }

        let advisor = LocalRetentionAdvisor()
        let availability = advisor.availability(
            localeIdentifier: transcript.localeIdentifier
        )
        retentionAdvisorAvailability = availability
        guard availability == .available else {
            retentionAdvisory = nil
            errorMessage = "Lokale Hinweise zur Zuschauerbindung sind auf diesem Mac oder für diese Sprache nicht verfügbar. Die gemessenen Struktur-Fakten und die manuelle Prüfung bleiben verfügbar."
            return
        }

        isAnalyzingRetention = true
        defer { isAnalyzingRetention = false }

        do {
            let advisory = try await advisor.analyze(
                transcript: transcript,
                structure: transcriptStructure
            )
            retentionAdvisory = advisory
            ledger.append(.init(
                timestamp: Date(),
                actor: .blackstock,
                stage: .editing,
                action: "local-retention-advisory-generated",
                summary: "Lokale Hinweise zur Zuschauerbindung und Struktur wurden aus Transkript und gemessenen Struktur-Fakten erstellt; sie sind keine Freigabe-Evidenz.",
                relatedSourceIDs: advisory.segmentIDs.map(\.uuidString),
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            retentionAdvisory = nil
            errorMessage = "Lokale Hinweise zur Zuschauerbindung konnten nicht erstellt werden: \(error.localizedDescription)"
        }
    }


    func supplementalAudioSetting(
        for captureID: UUID
    ) -> SupplementalAudioMixSetting {
        supplementalAudioMixSettings.first {
            $0.captureID == captureID
        } ?? SupplementalAudioMixSetting(
            captureID: captureID
        )
    }

    func setSupplementalAudioEnabled(
        captureID: UUID,
        enabled: Bool
    ) {
        updateSupplementalAudioMixSetting(
            captureID: captureID
        ) { setting in
            setting.enabled = enabled
        }

        renderArtifact = nil
        invalidateSavedClipRenders()
        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: enabled
                ? "supplemental-audio-enabled"
                : "supplemental-audio-disabled",
            summary: enabled
                ? "Zusätzliche Audiospur wurde für den nächsten finalen Render aktiviert."
                : "Zusätzliche Audiospur wurde aus dem nächsten finalen Render entfernt.",
            relatedSourceIDs: [captureID.uuidString],
            reversible: false,
            correlationID: correlationID
        ))
        persistWorkspaceIfPossible()
    }

    func setSupplementalAudioVolume(
        captureID: UUID,
        volume: Double
    ) {
        let clamped = min(max(volume, 0), 1)
        updateSupplementalAudioMixSetting(
            captureID: captureID
        ) { setting in
            setting.volume = clamped
        }

        renderArtifact = nil
        invalidateSavedClipRenders()
        ledger.append(.init(
            timestamp: Date(),
            actor: .user,
            stage: .editing,
            action: "supplemental-audio-volume-changed",
            summary:
                "Lautstärke der zusätzlichen Audiospur auf \(Int((clamped * 100).rounded())) % gesetzt.",
            relatedSourceIDs: [captureID.uuidString],
            reversible: false,
            correlationID: correlationID
        ))
        persistWorkspaceIfPossible()
    }

    private func updateSupplementalAudioMixSetting(
        captureID: UUID,
        change: (inout SupplementalAudioMixSetting) -> Void
    ) {
        if let index = supplementalAudioMixSettings.firstIndex(
            where: { $0.captureID == captureID }
        ) {
            change(&supplementalAudioMixSettings[index])
        } else {
            var setting = SupplementalAudioMixSetting(
                captureID: captureID
            )
            change(&setting)
            supplementalAudioMixSettings.append(setting)
        }
    }

    func render(projectID: UUID) async {
        guard let asset else {
            errorMessage = "Kein Produktionsmedium geladen."
            return
        }

        isRendering = true
        defer { isRendering = false }

        do {
            let store = try workspaceStore ?? makeWorkspaceStore()
            workspaceStore = store
            let directory = try store.renderDirectory(
                projectID: projectID
            )
            let outputURL = directory
                .appendingPathComponent("final")
                .appendingPathExtension("mp4")

            let supplementalAudio = supplementalAudioMixSettings
                .filter { $0.enabled && $0.volume > 0 }
                .compactMap { setting -> SupplementalAudioMixInput? in
                    guard let capture = supplementalCaptures.first(
                        where: {
                            $0.id == setting.captureID
                                && $0.mayBeUsedInProduction
                        }
                    ) else {
                        return nil
                    }
                    return SupplementalAudioMixInput(
                        captureID: capture.id,
                        fileURL: capture.fileURL,
                        volume: setting.volume
                    )
                }

            let artifact = try await LocalVideoRenderer().render(
                projectID: projectID,
                asset: asset,
                graph: graph,
                outputURL: outputURL,
                preset: renderPreset,
                transcript: transcript,
                burnInCaptions: burnInCaptionsEnabled,
                captionStyle: captionVisualStyle,
                supplementalAudio: supplementalAudio
            )
            renderArtifact = artifact
            packagingSuggestedTitle = nil
            await refreshAudioInspection(
                for: artifact.fileURL
            )
            ledger.append(.init(
                timestamp: Date(),
                actor: .blackstock,
                stage: .editing,
                action: "render-created",
                summary: "Lokaler MP4-Render wurde erstellt und validiert.",
                relatedSourceIDs: [artifact.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Render fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func refreshPreviewAfterHistoryChange() async {
        do {
            try await rebuildPreview()
            persistWorkspaceIfPossible()
            errorMessage = nil
        } catch {
            errorMessage = "Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    private func rebuildPreview() async throws {
        guard let asset else {
            player.replaceCurrentItem(with: nil)
            return
        }

        let source = AVURLAsset(url: asset.sourceURL)
        let composition = AVMutableComposition()

        let timeline = EditTimelineResolver().resolve(
            sourceDurationSeconds: asset.durationSeconds,
            operations: graph.currentOperations
        )
        guard timeline.hasContent else {
            throw CocoaError(.fileReadCorruptFile)
        }

        for sourceRange in timeline.sourceRanges {
            let range = CMTimeRange(
                start: CMTime(
                    seconds: sourceRange.startSeconds,
                    preferredTimescale: 600
                ),
                duration: CMTime(
                    seconds: sourceRange.durationSeconds,
                    preferredTimescale: 600
                )
            )
            try await composition.insertTimeRange(
                range,
                of: source,
                at: composition.duration
            )
        }
        let item = AVPlayerItem(asset: composition)

        if let reframe = graph.currentOperations
            .last(where: { $0.type == .reframe })?
            .reframeSpec {
            let sourceTracks = try await source.loadTracks(withMediaType: .video)
            let compositionTracks = composition.tracks(withMediaType: .video)

            if let sourceTrack = sourceTracks.first,
               let compositionTrack = compositionTracks.first {
                let naturalSize = try await sourceTrack.load(.naturalSize)
                let preferredTransform = try await sourceTrack.load(.preferredTransform)
                let renderSize = LocalRenderPreset.hd1080.renderSize(
                    for: reframe.aspectRatio
                )

                if let plan = ReframeTransformPlan.make(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    spec: reframe,
                    renderSize: renderSize
                ) {
                    let duration = composition.duration
                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = CMTimeRange(
                        start: .zero,
                        duration: duration
                    )

                    let layer = AVMutableVideoCompositionLayerInstruction(
                        assetTrack: compositionTrack
                    )
                    layer.setTransform(plan.transform, at: .zero)
                    instruction.layerInstructions = [layer]

                    let videoComposition = AVMutableVideoComposition()
                    videoComposition.instructions = [instruction]
                    videoComposition.renderSize = CGSize(
                        width: plan.renderWidth,
                        height: plan.renderHeight
                    )
                    videoComposition.frameDuration = CMTime(
                        value: 1,
                        timescale: 30
                    )
                    item.videoComposition = videoComposition
                }
            }
        }

        player.replaceCurrentItem(with: item)
        await player.seek(to: .zero)
    }

    private func clipTranscript(
        for candidate: LocalClipCandidate
    ) -> LocalTranscript? {
        guard let source =
                clipCandidateSourceTranscript else {
            return nil
        }
        return ClipTranscriptProjector()
            .project(
                source: source,
                candidate: candidate
            )
    }

    private func makeWorkspaceStore() throws -> ProjectWorkspaceStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base
            .appendingPathComponent("Blackstock", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return ProjectWorkspaceStore(rootURL: root)
    }

    private func persistWorkspaceIfPossible() {
        guard let projectID = activeProjectID,
              let storyboard else {
            return
        }

        do {
            let store = try workspaceStore ?? makeWorkspaceStore()
            workspaceStore = store
            let snapshot = StudioWorkspaceSnapshot(
                projectID: projectID,
                mediaAsset: asset,
                editGraph: graph,
                activityLedger: ledger,
                storyboard: storyboard,
                trimStart: trimStart,
                trimEnd: trimEnd,
                transcript: transcript,
                captionURL: captionURL,
                burnInCaptionsEnabled:
                    burnInCaptionsEnabled,
                captionVisualStyle:
                    captionVisualStyle,
                renderArtifact: renderArtifact,
                supplementalCaptures: supplementalCaptures,
                supplementalAudioMixSettings:
                    supplementalAudioMixSettings,
                savedClipSelections: savedClipSelections,
                updatedAt: Date()
            )
            try store.save(snapshot)
        } catch {
            errorMessage = "Automatisches Speichern des Projekt-Arbeitsbereichs fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func refreshAudioInspection(
        for url: URL
    ) async {
        do {
            audioTechnicalAssessment = try await LocalAudioTechnicalInspector()
                .inspect(url: url)
        } catch {
            audioTechnicalAssessment = nil
        }

        if audioTechnicalAssessment?.snapshot.hasAudioTrack == true {
            do {
                audioSignalAssessment = try await LocalAudioSignalAnalyzer()
                    .analyze(url: url)
            } catch {
                audioSignalAssessment = nil
            }

            do {
                audioLoudnessAssessment = try await LocalLoudnessAnalyzer()
                    .analyze(url: url)
            } catch {
                audioLoudnessAssessment = nil
            }
        } else {
            audioSignalAssessment = nil
            audioLoudnessAssessment = nil
        }
    }

    private func persistStoryboard(
        _ plan: StoryboardPlan
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(plan) else { return }
        UserDefaults.standard.set(
            data,
            forKey: "blackstock.storyboard.\(plan.projectID.uuidString)"
        )
    }

    private func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
#endif
