import XCTest
@testable import BlackstockCore

final class ClipTranscriptProjectorTests: XCTestCase {
    func testProjectionRebasesSegmentsToClipStart() throws {
        let firstID = UUID()
        let secondID = UUID()
        let source = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "eins zwei drei vier",
            segments: [
                .init(
                    id: firstID,
                    startSeconds: 10,
                    durationSeconds: 4,
                    text: "eins zwei",
                    confidence: 0.8
                ),
                .init(
                    id: secondID,
                    startSeconds: 15,
                    durationSeconds: 5,
                    text: "drei vier",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date(
                timeIntervalSince1970: 1
            )
        )
        let candidate = LocalClipCandidate(
            sourceRange: EditTimeRange(
                startSeconds: 9.5,
                durationSeconds: 11
            ),
            transcriptPreview:
                "eins zwei drei vier",
            wordCount: 4,
            averageConfidence: 0.85,
            segmentIDs: [firstID, secondID]
        )

        let projected = try XCTUnwrap(
            ClipTranscriptProjector().project(
                source: source,
                candidate: candidate
            )
        )

        XCTAssertEqual(
            projected.segments.count,
            2
        )
        XCTAssertEqual(
            projected.segments[0]
                .startSeconds,
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            projected.segments[1]
                .startSeconds,
            5.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            projected.text,
            "eins zwei drei vier"
        )
        XCTAssertTrue(projected.onDevice)
    }

    func testProjectionClampsSegmentAtClipEnd() throws {
        let id = UUID()
        let source = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "langer Satz",
            segments: [
                .init(
                    id: id,
                    startSeconds: 20,
                    durationSeconds: 10,
                    text: "langer Satz",
                    confidence: 0.7
                )
            ],
            onDevice: true,
            createdAt: Date()
        )
        let candidate = LocalClipCandidate(
            sourceRange: EditTimeRange(
                startSeconds: 18,
                durationSeconds: 7
            ),
            transcriptPreview: "langer Satz",
            wordCount: 2,
            averageConfidence: 0.7,
            segmentIDs: [id]
        )

        let projected = try XCTUnwrap(
            ClipTranscriptProjector().project(
                source: source,
                candidate: candidate
            )
        )

        XCTAssertEqual(
            projected.segments[0]
                .startSeconds,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            projected.segments[0]
                .durationSeconds,
            5,
            accuracy: 0.001
        )
    }

    func testProjectionDoesNotInventMissingSegments() {
        let source = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Text",
            segments: [
                .init(
                    startSeconds: 1,
                    durationSeconds: 2,
                    text: "Text",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date()
        )
        let candidate = LocalClipCandidate(
            sourceRange: EditTimeRange(
                startSeconds: 0,
                durationSeconds: 5
            ),
            transcriptPreview: "",
            wordCount: 0,
            averageConfidence: nil,
            segmentIDs: [UUID()]
        )

        XCTAssertNil(
            ClipTranscriptProjector().project(
                source: source,
                candidate: candidate
            )
        )
    }
}
