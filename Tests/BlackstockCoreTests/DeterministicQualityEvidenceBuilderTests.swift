import XCTest
@testable import BlackstockCore

final class DeterministicQualityEvidenceBuilderTests: XCTestCase {
    func testBuilderCoversOnlyGroundedRightsAndRenderAreas() {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact
        )

        XCTAssertEqual(
            review.coveredAreas,
            [.rightsAndPolicy, .renderIntegrity]
        )
        XCTAssertTrue(review.blockingFindings.isEmpty)
        XCTAssertEqual(
            review.missingCoverage(
                requiredAreas: [
                    .packaging,
                    .retentionStructure,
                    .audio,
                    .captions,
                    .visualComposition,
                    .rightsAndPolicy,
                    .renderIntegrity
                ]
            ),
            [
                .packaging,
                .retentionStructure,
                .audio,
                .captions,
                .visualComposition
            ]
        )
    }

    func testRealLocalTranscriptAddsCaptionCoverage() throws {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Hallo",
            segments: [
                .init(
                    startSeconds: 0,
                    durationSeconds: 1,
                    text: "Hallo",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date()
        )
        let captionURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vtt")
        try """
        WEBVTT

        00:00:00.000 --> 00:00:01.000
        Hallo
        """.write(
            to: captionURL,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: captionURL) }

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact,
            transcript: transcript,
            captionURL: captionURL
        )

        XCTAssertTrue(review.coveredAreas.contains(.captions))
        XCTAssertTrue(
            review.findings(in: .captions).contains {
                $0.title == "Captions lokal erzeugt und technisch validiert"
            }
        )
    }

    func testTechnicallyInvalidCaptionCreatesBlockingFinding() throws {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Hallo",
            segments: [
                .init(
                    startSeconds: 0,
                    durationSeconds: 1,
                    text: "Hallo",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date()
        )
        let captionURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vtt")
        try """
        WEBVTT

        00:00:00.000 --> 00:00:03.000
        Erster Cue.

        00:00:02.000 --> 00:00:04.000
        Zweiter Cue.
        """.write(
            to: captionURL,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: captionURL) }

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact,
            transcript: transcript,
            captionURL: captionURL
        )

        XCTAssertTrue(
            review.findings(in: .captions).contains {
                $0.severity == .blocker
                    && $0.title == "Caption-Datei technisch blockiert"
            }
        )
        XCTAssertFalse(review.blockingFindings.isEmpty)
    }

    func testFinalRenderAudioMeasurementsProvideGroundedAudioCoverage() {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let technical = AudioTechnicalAssessment.evaluate(
            .init(
                hasAudioTrack: true,
                sampleRateHz: 48_000,
                channelCount: 2,
                inspectedAt: Date()
            )
        )
        let signal = AudioSignalAssessment.evaluate(
            .init(
                peakDBFS: -1.0,
                rmsDBFS: -18.0,
                analyzedSampleCount: 1000,
                fullScaleSampleCount: 0,
                inspectedAt: Date()
            )
        )

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact,
            audioTechnicalAssessment: technical,
            audioSignalAssessment: signal
        )

        XCTAssertTrue(
            review.evidence.contains {
                $0.source == "Blackstock Local Audio Technical Inspector"
            }
        )
        XCTAssertTrue(
            review.evidence.contains {
                $0.source == "Blackstock Local PCM Analyzer"
            }
        )
        XCTAssertTrue(review.coveredAreas.contains(.audio))
        XCTAssertTrue(
            review.findings(in: .audio).contains {
                $0.title == "Audio des finalen Renders technisch analysiert"
                    && $0.severity == .info
            }
        )
        XCTAssertTrue(review.blockingFindings.isEmpty)
    }

    func testMissingAudioTrackCreatesBlockingAudioFinding() {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let technical = AudioTechnicalAssessment.evaluate(
            .init(
                hasAudioTrack: false,
                sampleRateHz: nil,
                channelCount: nil,
                inspectedAt: Date()
            )
        )

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact,
            audioTechnicalAssessment: technical
        )

        XCTAssertTrue(review.coveredAreas.contains(.audio))
        XCTAssertTrue(
            review.findings(in: .audio).contains {
                $0.title == "Keine Audiospur im Render"
                    && $0.severity == .blocker
            }
        )
        XCTAssertFalse(review.blockingFindings.isEmpty)
    }

    func testAudioWithoutAnalyzedSamplesCreatesBlockingFinding() {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let technical = AudioTechnicalAssessment.evaluate(
            .init(
                hasAudioTrack: true,
                sampleRateHz: 48_000,
                channelCount: 2,
                inspectedAt: Date()
            )
        )
        let signal = AudioSignalAssessment.evaluate(
            .init(
                peakDBFS: nil,
                rmsDBFS: nil,
                analyzedSampleCount: 0,
                fullScaleSampleCount: 0,
                inspectedAt: Date()
            )
        )

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact,
            audioTechnicalAssessment: technical,
            audioSignalAssessment: signal
        )

        XCTAssertTrue(
            review.findings(in: .audio).contains {
                $0.title == "Audioanalyse ohne Samples"
                    && $0.severity == .blocker
            }
        )
    }

    func testThumbnailFactsBecomeEvidenceWithoutAutoPassingPackaging() {
        let projectID = UUID()
        let asset = ProductionMediaAsset(
            displayName: "video.mov",
            sourceURL: URL(fileURLWithPath: "/tmp/video.mov"),
            durationSeconds: 10,
            authorization: .owned,
            rightsEvidence: ["eigene Aufnahme"],
            rightsAttestation: .init(
                confirmedByUser: true,
                attestedAt: Date()
            ),
            importedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let thumbnail = ThumbnailTechnicalAssessment.evaluate(
            .init(
                width: 3840,
                height: 2160,
                fileSizeBytes: 1_000_000,
                mimeType: "image/jpeg",
                inspectedAt: Date()
            )
        )

        let review = DeterministicQualityEvidenceBuilder().build(
            projectID: projectID,
            asset: asset,
            artifact: artifact,
            thumbnailAssessment: thumbnail
        )

        XCTAssertTrue(
            review.evidence.contains {
                $0.source == "Blackstock Thumbnail Technical Inspector"
            }
        )
        XCTAssertFalse(review.coveredAreas.contains(.packaging))
    }

}
