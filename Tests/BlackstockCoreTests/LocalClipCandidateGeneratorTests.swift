import XCTest
@testable import BlackstockCore

final class LocalClipCandidateGeneratorTests: XCTestCase {
    func testPauseSeparatedSpeechCreatesMultipleCandidates() {
        let transcript = makeTranscript([
            segment(0, 10, "Erster längerer Gedanke mit mehreren Worten"),
            segment(10.2, 8, "setzt den ersten Gedanken sinnvoll fort"),
            segment(22, 9, "Zweiter klar getrennter Gedanke beginnt hier"),
            segment(31.2, 8, "und wird danach noch weiter erklärt")
        ])

        let candidates = LocalClipCandidateGenerator().generate(
            transcript: transcript,
            sourceDurationSeconds: 45,
            minimumDurationSeconds: 15,
            maximumDurationSeconds: 75,
            pauseBoundarySeconds: 2.5
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertLessThan(candidates[0].sourceRange.endSeconds, 22)
        XCTAssertGreaterThanOrEqual(
            candidates[1].sourceRange.startSeconds,
            21.65
        )
        XCTAssertFalse(candidates[0].transcriptPreview.isEmpty)
        XCTAssertGreaterThan(candidates[0].wordCount, 0)
    }

    func testShortSpeechBlocksAreNotInventedAsCandidates() {
        let transcript = makeTranscript([
            segment(0, 4, "kurzer Satz"),
            segment(8, 3, "noch ein kurzer Satz")
        ])

        let candidates = LocalClipCandidateGenerator().generate(
            transcript: transcript,
            sourceDurationSeconds: 20,
            minimumDurationSeconds: 15
        )

        XCTAssertTrue(candidates.isEmpty)
    }

    func testCandidateStaysInsideSourceDuration() {
        let transcript = makeTranscript([
            segment(84, 8, "Ein Gedanke nahe am Ende des Videos"),
            segment(92.2, 8, "endet direkt an der Quellgrenze")
        ])

        let candidates = LocalClipCandidateGenerator().generate(
            transcript: transcript,
            sourceDurationSeconds: 100,
            minimumDurationSeconds: 15
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertLessThanOrEqual(
            candidates[0].sourceRange.endSeconds,
            100.000_001
        )
    }

    func testLongContinuousSpeechIsChunkedByMaximumDuration() {
        let segments = stride(from: 0.0, to: 120.0, by: 10.0)
            .map {
                segment(
                    $0,
                    9.5,
                    "fortlaufender Sprachabschnitt mit Inhalt"
                )
            }
        let transcript = makeTranscript(segments)

        let candidates = LocalClipCandidateGenerator().generate(
            transcript: transcript,
            sourceDurationSeconds: 130,
            minimumDurationSeconds: 15,
            maximumDurationSeconds: 35,
            pauseBoundarySeconds: 2.5,
            maximumCandidates: 8
        )

        XCTAssertGreaterThan(candidates.count, 1)
        XCTAssertTrue(
            candidates.allSatisfy {
                $0.sourceRange.durationSeconds <= 35.000_001
            }
        )
    }

    func testCandidateContainsOnlyFactualTranscriptMetadata() {
        let transcript = makeTranscript([
            TranscriptSegment(
                id: UUID(uuidString:
                    "00000000-0000-0000-0000-000000000001")!,
                startSeconds: 1,
                durationSeconds: 9,
                text: "eins zwei drei vier fünf",
                confidence: 0.8
            ),
            TranscriptSegment(
                id: UUID(uuidString:
                    "00000000-0000-0000-0000-000000000002")!,
                startSeconds: 10.2,
                durationSeconds: 9,
                text: "sechs sieben acht neun zehn",
                confidence: 0.6
            )
        ])

        let candidate = LocalClipCandidateGenerator().generate(
            transcript: transcript,
            sourceDurationSeconds: 30,
            minimumDurationSeconds: 15
        ).first

        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.wordCount, 10)
        XCTAssertEqual(
            candidate?.averageConfidence ?? 0,
            0.7,
            accuracy: 0.001
        )
        XCTAssertEqual(candidate?.segmentIDs.count, 2)
    }

    private func makeTranscript(
        _ segments: [TranscriptSegment]
    ) -> LocalTranscript {
        LocalTranscript(
            localeIdentifier: "de-DE",
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            onDevice: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func segment(
        _ start: Double,
        _ duration: Double,
        _ text: String
    ) -> TranscriptSegment {
        TranscriptSegment(
            startSeconds: start,
            durationSeconds: duration,
            text: text,
            confidence: 0.9
        )
    }
}
