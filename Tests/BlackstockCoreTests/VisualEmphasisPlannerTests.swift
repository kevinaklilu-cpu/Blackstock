import XCTest
@testable import BlackstockCore

final class VisualEmphasisPlannerTests: XCTestCase {
    func testNewFramingClearsOldZooms() {
        let operations = [
            EditOperation(type: .emphasis, timeRange: .init(startSeconds: 2, durationSeconds: 1), createdAt: Date()),
            EditOperation(type: .reframe, createdAt: Date())
        ]
        XCTAssertTrue(VisualEmphasisPlanner().cues(operations: operations, outputDurationSeconds: 20).isEmpty)
    }

    func testNonFiniteScaleIsRejected() {
        let operation = EditOperation(type: .emphasis,
            timeRange: .init(startSeconds: 2, durationSeconds: 1), value: .nan, createdAt: Date())
        XCTAssertTrue(VisualEmphasisPlanner().cues(operations: [operation], outputDurationSeconds: 20).isEmpty)
    }

    #if os(macOS)
    func testAutomaticZoomUsesSpeechPauseAndStaysInsideClip() {
        let transcript = LocalTranscript(localeIdentifier: "de-DE", text: "Hallo Welt",
            segments: [
                .init(startSeconds: 0, durationSeconds: 1, text: "Hallo", confidence: 1),
                .init(startSeconds: 2.3, durationSeconds: 1, text: "Welt", confidence: 1)
            ], onDevice: true, createdAt: Date())
        let cues = VisualEmphasisComposer.automaticCues(duration: 12, transcript: transcript)
        XCTAssertEqual(cues.first?.startSeconds, 2.3)
        XCTAssertTrue(cues.allSatisfy { $0.startSeconds + $0.durationSeconds <= 11.5 })
        XCTAssertTrue(VisualEmphasisComposer.automaticCues(duration: 3, transcript: nil).isEmpty)
    }
    #endif

    func testClampsScaleAndRejectsOverlappingCues() {
        let operations = [
            EditOperation(
                type: .emphasis,
                timeRange: .init(startSeconds: 2, durationSeconds: 1.2),
                value: 2,
                createdAt: Date()
            ),
            EditOperation(
                type: .emphasis,
                timeRange: .init(startSeconds: 2.5, durationSeconds: 1),
                value: 1.1,
                createdAt: Date()
            ),
            EditOperation(
                type: .emphasis,
                timeRange: .init(startSeconds: 8, durationSeconds: 4),
                value: 1.01,
                createdAt: Date()
            )
        ]

        let cues = VisualEmphasisPlanner().cues(
            operations: operations,
            outputDurationSeconds: 10
        )

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].scale, 1.18)
        XCTAssertEqual(cues[1].durationSeconds, 2)
        XCTAssertEqual(cues[1].scale, 1.03)
    }
}
