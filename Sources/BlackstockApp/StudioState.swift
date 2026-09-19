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

    private var correlationID = UUID()
    private var activeProjectID: UUID?
    private var workspaceStore: ProjectWorkspaceStore?

    func loadWorkspace(projectID: UUID) async {
        activeProjectID = projectID

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
                renderArtifact = snapshot.renderArtifact
                supplementalCaptures = snapshot.supplementalCaptures ?? []

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
                        await refreshAudioInspection(
                            for: asset.sourceURL
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
            graph = EditGraph(createdAt: Date())
            ledger = ActivityLedger()
            correlationID = UUID()
            trimStart = 0
            trimEnd = seconds
            lastUndoneRevisionID = nil
            renderArtifact = nil
            transcript = nil
            captionURL = nil
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

            let artifact = try await LocalVideoRenderer().render(
                projectID: projectID,
                asset: asset,
                graph: graph,
                outputURL: outputURL,
                preset: renderPreset
            )
            renderArtifact = artifact
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
                renderArtifact: renderArtifact,
                supplementalCaptures: supplementalCaptures,
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
