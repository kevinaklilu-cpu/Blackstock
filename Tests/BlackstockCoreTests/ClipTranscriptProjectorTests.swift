import XCTest
@testable import BlackstockCore

final class ClipTranscriptProjectorTests: XCTestCase {
    func testVisualClipsUseOnlyTheirOwnSpeechAndPublicationText() throws {
        let source = LocalTranscript(localeIdentifier: "de-DE", text: "Gesamtes Video", segments: [
            .init(startSeconds: 12, durationSeconds: 4, text: "Diese Kamera spart viel Energie.", confidence: 0.9),
            .init(startSeconds: 102, durationSeconds: 5, text: "Diese Pflanzen brauchen frisches Wasser.", confidence: 0.9)
        ], onDevice: true, createdAt: Date())
        func project(_ start: Double) throws -> LocalTranscript {
            try XCTUnwrap(ClipTranscriptProjector().project(source: source, candidate:
                .init(sourceRange: .init(startSeconds: start, durationSeconds: 20),
                      transcriptPreview: "", wordCount: 0, averageConfidence: nil, segmentIDs: [])))
        }
        let first = try project(10)
        let second = try project(100)
        XCTAssertEqual(first.text, "Diese Kamera spart viel Energie.")
        XCTAssertEqual(second.text, "Diese Pflanzen brauchen frisches Wasser.")
        XCTAssertEqual(second.segments.first?.startSeconds, 2)
        let a = StoryPublicationDraft.forClip(transcript: first, sourceURL: nil, start: 10, duration: 20, isShort: true)
        let b = StoryPublicationDraft.forClip(transcript: second, sourceURL: nil, start: 100, duration: 20, isShort: true)
        XCTAssertNotEqual(a.title, b.title)
        XCTAssertFalse(b.description.contains("Kamera"))
        XCTAssertTrue(b.description.contains("Pflanzen"))
    }

    func testDistinctMomentsExcludeContainedAndOverlappingDuplicates() {
        func candidate(_ start: Double, _ duration: Double) -> LocalClipCandidate {
            .init(sourceRange: .init(startSeconds: start, durationSeconds: duration),
                  transcriptPreview: "", wordCount: 0, averageConfidence: nil, segmentIDs: [])
        }
        let clips = [candidate(10, 30), candidate(12, 10), candidate(15, 30), candidate(60, 20), candidate(100, 25)]
        let ranker = LocalHighlightCandidateRanker()
        XCTAssertEqual(ranker.distinct(clips, limit: 8).map(\.id), [clips[0].id, clips[3].id, clips[4].id])
        XCTAssertEqual(ranker.distinct(clips, limit: 2).count, 2)
        XCTAssertTrue(ranker.distinct(clips, limit: 0).isEmpty)
    }

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
