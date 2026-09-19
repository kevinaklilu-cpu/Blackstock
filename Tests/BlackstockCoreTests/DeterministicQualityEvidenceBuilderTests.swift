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
        try "WEBVTT\n".write(
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
                $0.title == "Captions lokal erzeugt"
            }
        )
    }
    func testAudioMeasurementsBecomeEvidenceWithoutAutoPassingAudioGate() {
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
        XCTAssertFalse(review.coveredAreas.contains(.audio))
    }

}
