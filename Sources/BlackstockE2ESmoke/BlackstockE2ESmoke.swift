#if os(macOS)
@preconcurrency import AVFoundation
import BlackstockCore
import CoreMedia
import CoreVideo
import Foundation

@main
struct BlackstockE2ESmokeMain {
    @MainActor
    static func main() async {
        do {
            let outputURL = outputURLFromArguments()
            let result = try await CleanMachineScenario().run()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]
            let data = try encoder.encode(result)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(
                to: outputURL,
                options: [.atomic]
            )
            print("BLACKSTOCK_E2E_PASS")
            print(outputURL.path)
        } catch {
            fputs(
                "BLACKSTOCK_E2E_FAIL: \(error)\n",
                stderr
            )
            exit(1)
        }
    }

    private static func outputURLFromArguments() -> URL {
        let arguments = Array(
            CommandLine.arguments.dropFirst()
        )
        if let index = arguments.firstIndex(
            of: "--output"
        ),
        arguments.indices.contains(index + 1) {
            return URL(
                fileURLWithPath: arguments[index + 1]
            )
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blackstock-clean-machine-e2e.json"
            )
    }
}

private struct CleanMachineE2EResult:
    Codable,
    Sendable {
    let generatedSource: Bool
    let workspaceRightsDeclarationAccepted: Bool
    let opportunitySourceBound: Bool
    let localClipCandidateGenerated: Bool
    let supplementalVideoRendered: Bool
    let rendered: Bool
    let renderValidated: Bool
    let audioTrackValidated: Bool
    let pcmSamplesAnalyzed: Int64
    let integratedLUFS: Double
    let truePeakDBTP: Double
    let qualityReviewPassed: Bool
    let uploadVideoID: String
    let uploadJournalCommitted: Bool
    let analyticsViews: Int
    let learningFactCount: Int
    let persistenceRoundTrip: Bool
    let completedAt: Date
}

@MainActor
private struct CleanMachineScenario {
    func run() async throws
        -> CleanMachineE2EResult {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "Blackstock-E2E-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: root
            )
            E2EMockURLProtocol.handler = nil
        }

        let sourceURL = root.appendingPathComponent(
            "source.mov"
        )
        try await SyntheticMediaFactory()
            .createSourceMovie(
                at: sourceURL,
                durationSeconds: 4
            )
        try require(
            FileManager.default.fileExists(
                atPath: sourceURL.path
            ),
            "synthetic source missing"
        )

        let supplementalVideoURL = root
            .appendingPathComponent(
                "supplemental.mov"
            )
        try await SyntheticMediaFactory()
            .createSourceMovie(
                at: supplementalVideoURL,
                durationSeconds: 2.5
            )
        try require(
            FileManager.default.fileExists(
                atPath: supplementalVideoURL.path
            ),
            "synthetic supplemental video missing"
        )

        let sourceAsset = AVURLAsset(
            url: sourceURL
        )
        let sourceDuration = try await sourceAsset
            .load(.duration)
        let sourceDurationSeconds = CMTimeGetSeconds(
            sourceDuration
        )
        try require(
            sourceDurationSeconds > 3.5,
            "synthetic source duration invalid"
        )

        let projectID = UUID()
        var project = BlackstockProject(
            id: projectID,
            title: "Clean Machine E2E",
            targetChannelID: "channel-e2e",
            stage: .production,
            strategyVersion: 1,
            createdAt: Date(
                timeIntervalSince1970: 1
            ),
            updatedAt: Date(
                timeIntervalSince1970: 1
            )
        )
        let opportunitySource =
            MediaSourceReference(
                provider: .youtube,
                pageURL: URL(
                    string:
                        "https://www.youtube.com/watch?v=e2e-opportunity-123"
                )!,
                externalID:
                    "e2e-opportunity-123",
                discoveredAt: Date(
                    timeIntervalSince1970: 2
                )
            )
        let workspaceRights =
            WorkspaceRightsAttestation(
                channelID:
                    project.targetChannelID,
                confirmedByUser: true,
                attestedAt: Date(
                    timeIntervalSince1970: 2
                )
            )
        try require(
            workspaceRights
                .permitsUserDirectedProduction,
            "workspace rights declaration rejected"
        )

        let asset = ProductionMediaAsset(
            displayName: "source.mov",
            sourceURL: sourceURL,
            durationSeconds: sourceDurationSeconds,
            authorization:
                .userDeclaredResponsibility,
            rightsEvidence: [
                "Arbeitsbereich-Nutzererklärung "
                    + workspaceRights
                        .statementVersion,
                "Automatisch gebunden an youtube: "
                    + (
                        opportunitySource
                            .externalID
                        ?? "unbekannt"
                    )
            ],
            rightsAttestation: RightsAttestation(
                confirmedByUser: true,
                attestedAt: Date(
                    timeIntervalSince1970: 2
                ),
                statementVersion:
                    workspaceRights
                        .statementVersion
            ),
            originSource: opportunitySource,
            importedAt: Date(
                timeIntervalSince1970: 2
            )
        )
        try require(
            asset.mayEnterProduction,
            "rights gate rejected workspace-declared test media"
        )
        let opportunitySourceBound =
            asset.originSource?.id
                == opportunitySource.id
        try require(
            opportunitySourceBound,
            "production media lost opportunity provenance"
        )

        let resolution =
            MediaSourceResolver().resolve(
                opportunitySource,
                approvedProvider: nil
            )
        let readyPreparation =
            OpportunityClipPreparationPlanner()
            .snapshot(
                source: opportunitySource,
                resolution: resolution,
                hasBoundAuthorizedMedia: true,
                isGeneratingClips: false,
                clipCount: 0,
                observedAt: Date(
                    timeIntervalSince1970: 3
                )
            )
        try require(
            readyPreparation.status
                == .localProcessingReady,
            "bound opportunity did not become locally processable"
        )

        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text:
                "Erster zusammenhängender Gedanke mit echten Zeitsegmenten. "
                + "Der Gedanke wird im zweiten Segment fortgeführt.",
            segments: [
                TranscriptSegment(
                    startSeconds: 0.2,
                    durationSeconds: 1.2,
                    text:
                        "Erster zusammenhängender Gedanke mit echten Zeitsegmenten.",
                    confidence: 0.94
                ),
                TranscriptSegment(
                    startSeconds: 1.5,
                    durationSeconds: 1.2,
                    text:
                        "Der Gedanke wird im zweiten Segment fortgeführt.",
                    confidence: 0.91
                )
            ],
            onDevice: true,
            createdAt: Date(
                timeIntervalSince1970: 3
            )
        )
        let clipCandidates =
            LocalClipCandidateGenerator()
            .generate(
                transcript: transcript,
                sourceDurationSeconds:
                    sourceDurationSeconds,
                minimumDurationSeconds: 2,
                maximumDurationSeconds: 3.6,
                pauseBoundarySeconds: 2.5,
                maximumCandidates: 4
            )
        let selectedClip = try unwrap(
            clipCandidates.first,
            "opportunity-bound local clip candidate missing"
        )
        let clipPreparation =
            OpportunityClipPreparationPlanner()
            .snapshot(
                source: opportunitySource,
                resolution: resolution,
                hasBoundAuthorizedMedia: true,
                isGeneratingClips: false,
                clipCount:
                    clipCandidates.count,
                observedAt: Date(
                    timeIntervalSince1970: 3
                )
            )
        try require(
            clipPreparation.status
                == .clipsAvailable,
            "local clip job did not expose available clips"
        )

        var graph = EditGraph(
            createdAt: Date(
                timeIntervalSince1970: 3
            )
        )
        _ = graph.apply(
            EditOperation(
                type: .trim,
                timeRange:
                    selectedClip.sourceRange,
                createdAt: Date(
                    timeIntervalSince1970: 4
                )
            ),
            actor: .user
        )

        let renderURL = root
            .appendingPathComponent("final.mp4")
        let artifact = try await LocalVideoRenderer()
            .render(
                projectID: projectID,
                asset: asset,
                graph: graph,
                outputURL: renderURL,
                preset: .hd1080,
                supplementalVideo: [
                    SupplementalVideoInsertInput(
                        captureID: UUID(),
                        fileURL: supplementalVideoURL,
                        timelineStartSeconds: 0.8,
                        sourceStartSeconds: 0.2,
                        durationSeconds: 1.4
                    )
                ]
            )
        try require(
            artifact.hasCurrentTechnicalValidation,
            "render validation did not pass"
        )

        let technical = try await
            LocalAudioTechnicalInspector()
            .inspect(url: renderURL)
        try require(
            technical.snapshot.hasAudioTrack,
            "render has no audio track"
        )

        let signal = try await
            LocalAudioSignalAnalyzer()
            .analyze(url: renderURL)
        try require(
            signal.snapshot.analyzedSampleCount > 0,
            "PCM analyzer saw no samples"
        )

        let loudness = try await
            LocalLoudnessAnalyzer()
            .analyze(url: renderURL)
        let integrated = try unwrap(
            loudness.snapshot.integratedLUFS,
            "integrated loudness missing"
        )
        let truePeak = try unwrap(
            loudness.snapshot.truePeakDBTP,
            "true peak missing"
        )

        let review =
            DeterministicQualityEvidenceBuilder()
            .build(
                projectID: projectID,
                asset: asset,
                artifact: artifact,
                audioTechnicalAssessment:
                    technical,
                audioSignalAssessment: signal,
                audioLoudnessAssessment:
                    loudness
            )
        try require(
            review.blockingFindings.isEmpty,
            "technical quality review blocked"
        )
        try require(
            review.findings(in: .audio)
                .contains {
                    $0.title
                        == "Audio des finalen Renders professionell gemessen"
                },
            "professional audio evidence missing"
        )

        for destination in [
            BlackstockStage.preview,
            .storyboard,
            .editing,
            .packaging,
            .review,
            .publishing
        ] {
            try require(
                project.advance(
                    to: destination,
                    at: Date()
                ),
                "canonical stage transition failed: "
                    + destination.rawValue
            )
        }

        let session = makeMockSession()
        let journalURL = root
            .appendingPathComponent(
                "external-actions.json"
            )
        let journal = try ExternalActionJournal
            .persistent(at: journalURL)

        let uploadResult =
            try await YouTubeResumableUploader(
                accessToken: "e2e-token",
                chunkSize: 64 * 1024 * 1024
            )
            .upload(
                artifact: artifact,
                project: project,
                workspaceChannelID:
                    project.targetChannelID,
                authorizedUploadChannelID:
                    project.targetChannelID,
                metadata:
                    YouTubeUploadMetadata(
                        title: "Clean Machine E2E",
                        description:
                            "Deterministischer lokaler CI-Test.",
                        defaultLanguage: "de-DE",
                        defaultAudioLanguage:
                            "de-DE",
                        privacyStatus:
                            .privateVideo,
                        selfDeclaredMadeForKids:
                            false
                    ),
                rightsValidated: true,
                quotaState: .unknown,
                networkAvailable: true,
                journal: journal,
                session: session,
                now: Date()
            )

        try require(
            uploadResult.videoID
                == "e2e-video-123",
            "mock upload video ID mismatch"
        )

        let reloadedJournal =
            try ExternalActionJournal
            .persistent(at: journalURL)
        let journalEntry =
            await reloadedJournal.entry(
                for: uploadResult
                    .idempotencyKey
            )
        let journalCommitted =
            journalEntry?.state.rawValue
                == ExternalActionState
                    .remoteCommitted.rawValue
        try require(
            journalCommitted,
            "upload journal did not persist commit"
        )

        try require(
            project.advance(
                to: .published,
                at: Date()
            ),
            "publishing -> published transition failed"
        )

        let analytics =
            try await YouTubeAnalyticsClient(
                accessToken: "e2e-token",
                channelID:
                    project.targetChannelID
            )
            .snapshot(
                startDate: "2026-09-01",
                endDate: "2026-09-07",
                videoID:
                    uploadResult.videoID,
                session: session,
                now: Date(
                    timeIntervalSince1970:
                        1_789_000_000
                )
            )
        try require(
            analytics.views == 1234,
            "analytics mock was not decoded"
        )

        var published = PublishedVideoRecord(
            projectID: project.id,
            experimentID: nil,
            targetChannelID:
                project.targetChannelID,
            youtubeVideoID:
                uploadResult.videoID,
            publishedAt: Date(
                timeIntervalSince1970:
                    1_788_000_000
            )
        )
        try GrowthAnalyticsContextGuard()
            .validate(
                project: project,
                record: published
            )
        published.observations.append(
            GrowthObservation(
                window: .first7Days,
                analytics: analytics,
                collectedAt:
                    analytics.retrievedAt
            )
        )

        let learning = try unwrap(
            GrowthLearningEngine()
                .summarize(published),
            "growth learning missing"
        )
        try require(
            !learning.facts.isEmpty,
            "growth learning has no facts"
        )
        try require(
            learning.facts.contains {
                $0.contains("1234 Views")
            },
            "growth learning lost observed views"
        )

        let growthStore = GrowthRecordStore(
            rootURL: root
                .appendingPathComponent(
                    "Growth",
                    isDirectory: true
                )
        )
        try growthStore.save(
            record: published
        )
        try growthStore.save(
            learning: learning,
            projectID: project.id
        )
        let recordRoundTrip =
            try growthStore.loadRecord(
                projectID: project.id
            )
        let learningRoundTrip =
            try growthStore.loadLearning(
                projectID: project.id
            )
        let persistenceRoundTrip =
            recordRoundTrip == published
            && learningRoundTrip == learning
        try require(
            persistenceRoundTrip,
            "growth persistence round-trip failed"
        )

        return CleanMachineE2EResult(
            generatedSource: true,
            workspaceRightsDeclarationAccepted:
                workspaceRights
                    .permitsUserDirectedProduction,
            opportunitySourceBound:
                opportunitySourceBound,
            localClipCandidateGenerated:
                !clipCandidates.isEmpty,
            supplementalVideoRendered:
                FileManager.default.fileExists(
                    atPath: supplementalVideoURL.path
                ),
            rendered: FileManager.default
                .fileExists(
                    atPath: renderURL.path
                ),
            renderValidated:
                artifact
                    .hasCurrentTechnicalValidation,
            audioTrackValidated:
                technical.snapshot.hasAudioTrack,
            pcmSamplesAnalyzed:
                signal.snapshot
                    .analyzedSampleCount,
            integratedLUFS: integrated,
            truePeakDBTP: truePeak,
            qualityReviewPassed:
                review.blockingFindings.isEmpty,
            uploadVideoID:
                uploadResult.videoID,
            uploadJournalCommitted:
                journalCommitted,
            analyticsViews:
                analytics.views ?? 0,
            learningFactCount:
                learning.facts.count,
            persistenceRoundTrip:
                persistenceRoundTrip,
            completedAt: Date()
        )
    }

    private func makeMockSession()
        -> URLSession {
        E2EMockURLProtocol.handler = {
            request in
            let url = try unwrap(
                request.url,
                "mock request URL missing"
            )

            if request.httpMethod == "POST",
               url.host == "www.googleapis.com",
               url.path.contains(
                    "/upload/youtube/v3/videos"
               ) {
                return (
                    try httpResponse(
                        url: url,
                        statusCode: 200,
                        headers: [
                            "Location":
                                "https://upload.blackstock.invalid/session"
                        ]
                    ),
                    Data()
                )
            }

            if request.httpMethod == "PUT",
               url.host
                == "upload.blackstock.invalid" {
                return (
                    try httpResponse(
                        url: url,
                        statusCode: 200,
                        headers: [
                            "Content-Type":
                                "application/json"
                        ]
                    ),
                    Data(
                        #"{"id":"e2e-video-123"}"#
                            .utf8
                    )
                )
            }

            if url.host
                == "youtubeanalytics.googleapis.com" {
                let body = """
                {
                  "columnHeaders": [
                    {"name":"views"},
                    {"name":"engagedViews"},
                    {"name":"likes"},
                    {"name":"comments"},
                    {"name":"shares"},
                    {"name":"estimatedMinutesWatched"},
                    {"name":"averageViewDuration"},
                    {"name":"averageViewPercentage"},
                    {"name":"subscribersGained"},
                    {"name":"subscribersLost"}
                  ],
                  "rows": [[
                    1234,
                    1000,
                    98,
                    12,
                    7,
                    3210.5,
                    132.0,
                    61.5,
                    17,
                    2
                  ]]
                }
                """
                return (
                    try httpResponse(
                        url: url,
                        statusCode: 200,
                        headers: [
                            "Content-Type":
                                "application/json"
                        ]
                    ),
                    Data(body.utf8)
                )
            }

            throw E2EError(
                message:
                    "unexpected mock request: "
                    + (request.httpMethod
                        ?? "UNKNOWN")
                    + " "
                    + url.absoluteString
            )
        }

        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            E2EMockURLProtocol.self
        ]
        return URLSession(
            configuration: configuration
        )
    }
}

private final class E2EMockURLProtocol:
    URLProtocol {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws
            -> (HTTPURLResponse, Data))?

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: E2EError(
                    message:
                        "mock URL handler missing"
                )
            )
            return
        }

        do {
            let (response, data) =
                try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(
                self,
                didLoad: data
            )
            client?.urlProtocolDidFinishLoading(
                self
            )
        } catch {
            client?.urlProtocol(
                self,
                didFailWithError: error
            )
        }
    }

    override func stopLoading() {}
}

@MainActor
private struct SyntheticMediaFactory {
    func createSourceMovie(
        at outputURL: URL,
        durationSeconds: Double
    ) async throws {
        let videoURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "synthetic-video.mov"
            )
        let audioURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "synthetic-audio.caf"
            )

        try await createVideo(
            at: videoURL,
            durationSeconds: durationSeconds
        )
        try createAudio(
            at: audioURL,
            durationSeconds: durationSeconds
        )
        try await mux(
            videoURL: videoURL,
            audioURL: audioURL,
            outputURL: outputURL
        )
    }

    private func createVideo(
        at url: URL,
        durationSeconds: Double
    ) async throws {
        try? FileManager.default
            .removeItem(at: url)

        let width = 1_920
        let height = 1_080
        let frameRate = 30
        let frameCount = Int(
            (durationSeconds
                * Double(frameRate))
                .rounded(.down)
        )

        let writer = try AVAssetWriter(
            outputURL: url,
            fileType: .mov
        )
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey:
                    AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey:
                        2_000_000
                ]
            ]
        )
        input.expectsMediaDataInRealTime =
            false

        let adaptor =
            AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey
                        as String:
                        Int(
                            kCVPixelFormatType_32BGRA
                        ),
                    kCVPixelBufferWidthKey
                        as String: width,
                    kCVPixelBufferHeightKey
                        as String: height
                ]
            )

        guard writer.canAdd(input) else {
            throw E2EError(
                message:
                    "cannot add synthetic video input"
            )
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error
                ?? E2EError(
                    message:
                        "synthetic video writer failed to start"
                )
        }
        writer.startSession(
            atSourceTime: .zero
        )

        for frame in 0..<frameCount {
            while !input
                .isReadyForMoreMediaData {
                try await Task.sleep(
                    nanoseconds: 1_000_000
                )
            }

            var pixelBuffer:
                CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            )
            guard status
                    == kCVReturnSuccess,
                  let pixelBuffer else {
                throw E2EError(
                    message:
                        "synthetic pixel buffer allocation failed"
                )
            }

            CVPixelBufferLockBaseAddress(
                pixelBuffer,
                []
            )
            if let base =
                CVPixelBufferGetBaseAddress(
                    pixelBuffer
                ) {
                let size =
                    CVPixelBufferGetDataSize(
                        pixelBuffer
                    )
                let value = UInt8(
                    32 + (frame % 160)
                )
                base.initializeMemory(
                    as: UInt8.self,
                    repeating: value,
                    count: size
                )
            }
            CVPixelBufferUnlockBaseAddress(
                pixelBuffer,
                []
            )

            let timestamp = CMTime(
                value: CMTimeValue(frame),
                timescale:
                    CMTimeScale(frameRate)
            )
            guard adaptor.append(
                pixelBuffer,
                withPresentationTime:
                    timestamp
            ) else {
                throw writer.error
                    ?? E2EError(
                        message:
                            "synthetic frame append failed"
                    )
            }
        }

        input.markAsFinished()
        try await finish(writer)
    }

    private func createAudio(
        at url: URL,
        durationSeconds: Double
    ) throws {
        try? FileManager.default
            .removeItem(at: url)

        guard let format = AVAudioFormat(
            commonFormat:
                .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ) else {
            throw E2EError(
                message:
                    "synthetic audio format unavailable"
            )
        }

        let totalFrames = AVAudioFrameCount(
            (durationSeconds * 48_000)
                .rounded(.down)
        )
        guard let buffer =
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: totalFrames
            ),
            let channels =
                buffer.floatChannelData else {
            throw E2EError(
                message:
                    "synthetic audio buffer unavailable"
            )
        }
        buffer.frameLength = totalFrames

        for frame in 0..<Int(totalFrames) {
            let value = Float(
                0.15
                * sin(
                    2
                    * Double.pi
                    * 997
                    * Double(frame)
                    / 48_000
                )
            )
            channels[0][frame] = value
            channels[1][frame] = value
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try file.write(from: buffer)
    }

    private func mux(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL
    ) async throws {
        try? FileManager.default
            .removeItem(at: outputURL)

        let videoAsset = AVURLAsset(
            url: videoURL
        )
        let audioAsset = AVURLAsset(
            url: audioURL
        )
        let videoTracks = try await
            videoAsset.loadTracks(
                withMediaType: .video
            )
        let audioTracks = try await
            audioAsset.loadTracks(
                withMediaType: .audio
            )
        let videoTrack = try unwrap(
            videoTracks.first,
            "synthetic video track missing"
        )
        let audioTrack = try unwrap(
            audioTracks.first,
            "synthetic audio track missing"
        )
        let duration = try await videoAsset
            .load(.duration)

        let composition =
            AVMutableComposition()
        let compositionVideo =
            try unwrap(
                composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID:
                        kCMPersistentTrackID_Invalid
                ),
                "composition video track unavailable"
            )
        let compositionAudio =
            try unwrap(
                composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID:
                        kCMPersistentTrackID_Invalid
                ),
                "composition audio track unavailable"
            )
        let range = CMTimeRange(
            start: .zero,
            duration: duration
        )
        try compositionVideo.insertTimeRange(
            range,
            of: videoTrack,
            at: .zero
        )
        try compositionAudio.insertTimeRange(
            range,
            of: audioTrack,
            at: .zero
        )

        let exporter = try unwrap(
            AVAssetExportSession(
                asset: composition,
                presetName:
                    AVAssetExportPresetHighestQuality
            ),
            "synthetic mux exporter unavailable"
        )
        guard exporter.supportedFileTypes
                .contains(.mov) else {
            throw E2EError(
                message:
                    "synthetic mux does not support MOV"
            )
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse =
            true

        try await export(exporter)
    }

    private func finish(
        _ writer: AVAssetWriter
    ) async throws {
        try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        Void,
                        Error
                    >
            ) in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing:
                            writer.error
                            ?? E2EError(
                                message:
                                    "synthetic writer did not complete"
                            )
                    )
                }
            }
        }
    }

    private func export(
        _ exporter: AVAssetExportSession
    ) async throws {
        try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<
                        Void,
                        Error
                    >
            ) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing:
                            exporter.error
                            ?? E2EError(
                                message:
                                    "synthetic mux export failed"
                            )
                    )
                default:
                    continuation.resume(
                        throwing:
                            E2EError(
                                message:
                                    "synthetic mux ended in state \(exporter.status.rawValue)"
                            )
                    )
                }
            }
        }
    }
}

private struct E2EError:
    Error,
    LocalizedError,
    CustomStringConvertible {
    let message: String

    var errorDescription: String? {
        message
    }

    var description: String {
        message
    }
}

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    if !condition() {
        throw E2EError(
            message: message
        )
    }
}

private func unwrap<T>(
    _ value: T?,
    _ message: String
) throws -> T {
    guard let value else {
        throw E2EError(
            message: message
        )
    }
    return value
}

private func httpResponse(
    url: URL,
    statusCode: Int,
    headers: [String: String]
) throws -> HTTPURLResponse {
    try unwrap(
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ),
        "HTTPURLResponse creation failed"
    )
}
#endif
