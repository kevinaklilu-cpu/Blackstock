import XCTest
@testable import BlackstockCore

final class LocalRetentionAdvisorTests: XCTestCase {
    func testInputUsesOnlyRequestedOpeningWindowAndMeasuredFacts() {
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "A B C",
            segments: [
                .init(
                    startSeconds: 2,
                    durationSeconds: 1,
                    text: "A",
                    confidence: 0.9
                ),
                .init(
                    startSeconds: 40,
                    durationSeconds: 1,
                    text: "B",
                    confidence: 0.9
                ),
                .init(
                    startSeconds: 120,
                    durationSeconds: 1,
                    text: "C",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date()
        )
        let structure = TranscriptStructureAnalyzer().analyze(
            transcript: transcript
        )

        let input = RetentionAnalysisInput.make(
            transcript: transcript,
            structure: structure,
            maxSeconds: 90
        )

        XCTAssertTrue(input.transcriptExcerpt.contains("[2.0s] A"))
        XCTAssertTrue(input.transcriptExcerpt.contains("[40.0s] B"))
        XCTAssertFalse(input.transcriptExcerpt.contains("C"))
        XCTAssertEqual(input.segmentIDs.count, 2)
        XCTAssertFalse(input.structureFacts.isEmpty)
    }

    func testAdvisoryIsNeverReleaseEvidenceByDefault() {
        let advisory = LocalRetentionAdvisory(
            text: "Hinweis",
            source: "On-Device",
            segmentIDs: [],
            createdAt: Date()
        )
        XCTAssertFalse(advisory.isReleaseEvidence)
    }
}
