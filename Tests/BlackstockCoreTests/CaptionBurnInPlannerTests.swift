import XCTest
@testable import BlackstockCore

final class CaptionBurnInPlannerTests: XCTestCase {
    func testPlannerKeepsValidTranscriptTiming() {
        let transcript = makeTranscript([
            .init(
                startSeconds: 2,
                durationSeconds: 3,
                text: "Erste Caption",
                confidence: 0.9
            ),
            .init(
                startSeconds: 7,
                durationSeconds: 2.5,
                text: "Zweite Caption",
                confidence: 0.8
            )
        ])

        let cues = CaptionBurnInPlanner().cues(
            transcript: transcript,
            outputDurationSeconds: 12
        )

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(
            cues[0].startSeconds,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            cues[0].durationSeconds,
            3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            cues[0].text,
            "Erste Caption"
        )
    }

    func testPlannerClampsCaptionAtOutputEnd() {
        let transcript = makeTranscript([
            .init(
                startSeconds: 8,
                durationSeconds: 5,
                text: "Caption am Ende",
                confidence: 0.9
            )
        ])

        let cues = CaptionBurnInPlanner().cues(
            transcript: transcript,
            outputDurationSeconds: 10
        )

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(
            cues[0].startSeconds,
            8,
            accuracy: 0.001
        )
        XCTAssertEqual(
            cues[0].durationSeconds,
            2,
            accuracy: 0.001
        )
    }

    func testPlannerDropsEmptyAndOutOfRangeSegments() {
        let transcript = makeTranscript([
            .init(
                startSeconds: 1,
                durationSeconds: 1,
                text: "   ",
                confidence: 0.9
            ),
            .init(
                startSeconds: 20,
                durationSeconds: 2,
                text: "Außerhalb",
                confidence: 0.9
            ),
            .init(
                startSeconds: 3,
                durationSeconds: 0.01,
                text: "Zu kurz",
                confidence: 0.9
            )
        ])

        let cues = CaptionBurnInPlanner().cues(
            transcript: transcript,
            outputDurationSeconds: 10
        )

        XCTAssertTrue(cues.isEmpty)
    }

    func testPlannerRejectsNonPositiveOutputDuration() {
        let transcript = makeTranscript([
            .init(
                startSeconds: 0,
                durationSeconds: 2,
                text: "Text",
                confidence: 0.9
            )
        ])

        XCTAssertTrue(
            CaptionBurnInPlanner().cues(
                transcript: transcript,
                outputDurationSeconds: 0
            ).isEmpty
        )
    }

    private func makeTranscript(
        _ segments: [TranscriptSegment]
    ) -> LocalTranscript {
        LocalTranscript(
            localeIdentifier: "de-DE",
            text: segments.map(\.text)
                .joined(separator: " "),
            segments: segments,
            onDevice: true,
            createdAt: Date(
                timeIntervalSince1970: 1
            )
        )
    }
}
