import XCTest
@testable import BlackstockCore

final class SpeechCleanupTests: XCTestCase {
    func testPlannerFindsFillerWordsAndKeepsNaturalPausePadding() {
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Hallo äh weiter",
            segments: [
                .init(startSeconds: 0, durationSeconds: 0.5, text: "Hallo", confidence: 1),
                .init(startSeconds: 0.7, durationSeconds: 0.2, text: "äh", confidence: 1),
                .init(startSeconds: 2.5, durationSeconds: 0.5, text: "weiter", confidence: 1)
            ],
            onDevice: true,
            createdAt: Date()
        )

        let plan = LocalSpeechCleanupPlanner().plan(
            transcript: transcript,
            outputDurationSeconds: 4
        )

        XCTAssertEqual(plan.suggestions.map(\.reason), [.fillerWord, .longPause])
        XCTAssertEqual(plan.suggestions[1].outputRange.startSeconds, 1.15, accuracy: 0.001)
        XCTAssertEqual(plan.suggestions[1].outputRange.endSeconds, 2.25, accuracy: 0.001)
    }

    func testOutputRangeMapsAcrossExistingSourceCuts() {
        let plan = EditTimelinePlan(sourceRanges: [
            .init(startSeconds: 2, durationSeconds: 3),
            .init(startSeconds: 8, durationSeconds: 4)
        ])

        let mapped = plan.sourceRanges(forOutputRange: .init(
            startSeconds: 2.5,
            durationSeconds: 2
        ))

        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped[0].startSeconds, 4.5, accuracy: 0.001)
        XCTAssertEqual(mapped[0].durationSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(mapped[1].startSeconds, 8, accuracy: 0.001)
        XCTAssertEqual(mapped[1].durationSeconds, 1.5, accuracy: 0.001)
    }
}
