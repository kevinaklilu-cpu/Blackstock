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

    private var correlationID = UUID()

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
    }

    func removeStoryboardBeat(id: UUID) {
        guard var plan = storyboard else { return }
        guard plan.removeBeat(id: id, at: Date()) else { return }
        storyboard = plan
        persistStoryboard(plan)
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
    }

    func importMovie(
        url: URL,
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
            let avAsset = AVURLAsset(url: url)
            let duration = try await avAsset.load(.duration)
            let seconds = max(CMTimeGetSeconds(duration), 0)

            let imported = ProductionMediaAsset(
                displayName: url.lastPathComponent,
                sourceURL: url,
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

            do {
                audioTechnicalAssessment = try await LocalAudioTechnicalInspector()
                    .inspect(url: imported.sourceURL)
            } catch {
                audioTechnicalAssessment = nil
            }

            if audioTechnicalAssessment?.snapshot.hasAudioTrack == true {
                do {
                    audioSignalAssessment = try await LocalAudioSignalAnalyzer()
                        .analyze(url: imported.sourceURL)
                } catch {
                    audioSignalAssessment = nil
                }
            } else {
                audioSignalAssessment = nil
            }

            errorMessage = nil
        } catch {
            errorMessage = "Video konnte nicht geladen werden: \(error.localizedDescription)"
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
            errorMessage = nil
        } catch {
            errorMessage = "Vorschau konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func undo() async {
        let undone = graph.headID
        guard let restored = graph.undo() else { return }
        lastUndoneRevisionID = undone
        renderArtifact = nil
        transcript = nil
        captionURL = nil
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
    }

    func redo() async {
        guard let id = lastUndoneRevisionID,
              let restored = graph.redo(to: id) else { return }
        lastUndoneRevisionID = nil
        renderArtifact = nil
        transcript = nil
        captionURL = nil
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
            let localTranscript = try await transcriber.transcribeVideo(
                url: asset.sourceURL,
                localeIdentifier: localeIdentifier
            )

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Blackstock-Captions", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
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
                summary: "On-Device-Transkript und WebVTT-Captions wurden lokal erzeugt.",
                relatedSourceIDs: [asset.id.uuidString],
                reversible: false,
                correlationID: correlationID
            ))
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
            errorMessage = "Lokale Retention-Hinweise sind auf diesem Mac oder für diese Sprache nicht verfügbar. Die gemessenen Struktur-Fakten und die manuelle Review bleiben verfügbar."
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
                summary: "Lokale Retention-/Strukturhinweise wurden aus Transkript und gemessenen Struktur-Fakten erstellt; sie sind keine Release-Evidenz.",
                relatedSourceIDs: advisory.segmentIDs.map(\.uuidString),
                reversible: false,
                correlationID: correlationID
            ))
            errorMessage = nil
        } catch {
            retentionAdvisory = nil
            errorMessage = "Lokale Retention-Hinweise konnten nicht erstellt werden: \(error.localizedDescription)"
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
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Blackstock-Renders", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let outputURL = directory
                .appendingPathComponent(projectID.uuidString)
                .appendingPathExtension("mp4")

            let artifact = try await LocalVideoRenderer().render(
                projectID: projectID,
                asset: asset,
                graph: graph,
                outputURL: outputURL,
                preset: renderPreset
            )
            renderArtifact = artifact
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
            errorMessage = nil
        } catch {
            errorMessage = "Render fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func refreshPreviewAfterHistoryChange() async {
        do {
            try await rebuildPreview()
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

        let trim = graph.currentOperations.last(where: { $0.type == .trim })?.timeRange
        let range: CMTimeRange
        if let trim {
            range = CMTimeRange(
                start: CMTime(seconds: trim.startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: trim.durationSeconds, preferredTimescale: 600)
            )
        } else {
            range = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: asset.durationSeconds, preferredTimescale: 600)
            )
        }

        try await composition.insertTimeRange(range, of: source, at: .zero)
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
