import XCTest
@testable import BlackstockCore

final class LocalTranscriptEditorTests: XCTestCase {
    private let firstID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    )!
    private let secondID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000002"
    )!

    func testEditsTextAndTimingWithoutChangingSegmentIdentity() throws {
        let transcript = makeTranscript()

        let edited = try LocalTranscriptEditor().updatingSegment(
            in: transcript,
            id: firstID,
            text: "Korrigierter Untertitel",
            startSeconds: 0.25,
            durationSeconds: 1.5,
            outputDurationSeconds: 5,
            editedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(edited.segments[0].id, firstID)
        XCTAssertEqual(
            edited.segments[0].text,
            "Korrigierter Untertitel"
        )
        XCTAssertEqual(
            edited.segments[0].startSeconds,
            0.25,
            accuracy: 0.001
        )
        XCTAssertEqual(
            edited.segments[0].durationSeconds,
            1.5,
            accuracy: 0.001
        )
        XCTAssertTrue(edited.segments[0].wasEditedByUser)
        XCTAssertEqual(
            edited.text,
            "Korrigierter Untertitel zweiter Text"
        )
    }

    func testRejectsOverlap() {
        XCTAssertThrowsError(
            try LocalTranscriptEditor().updatingSegment(
                in: makeTranscript(),
                id: firstID,
                text: "Überlappung",
                startSeconds: 0,
                durationSeconds: 2.5,
                outputDurationSeconds: 5
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptionSegmentEditError,
                .overlappingSegments
            )
        }
    }

    func testRejectsEmptyCaptionText() {
        XCTAssertThrowsError(
            try LocalTranscriptEditor().updatingSegment(
                in: makeTranscript(),
                id: firstID,
                text: "   ",
                startSeconds: 0,
                durationSeconds: 1,
                outputDurationSeconds: 5
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptionSegmentEditError,
                .emptyText
            )
        }
    }

    func testRejectsSegmentBeyondEditedTimeline() {
        XCTAssertThrowsError(
            try LocalTranscriptEditor().updatingSegment(
                in: makeTranscript(),
                id: secondID,
                text: "zweiter Text",
                startSeconds: 4,
                durationSeconds: 2,
                outputDurationSeconds: 5
            )
        ) { error in
            XCTAssertEqual(
                error as? CaptionSegmentEditError,
                .outsideOutputDuration
            )
        }
    }

    private func makeTranscript() -> LocalTranscript {
        LocalTranscript(
            localeIdentifier: "de-DE",
            text: "erster Text zweiter Text",
            segments: [
                TranscriptSegment(
                    id: firstID,
                    startSeconds: 0,
                    durationSeconds: 1.5,
                    text: "erster Text",
                    confidence: 0.8
                ),
                TranscriptSegment(
                    id: secondID,
                    startSeconds: 2,
                    durationSeconds: 1,
                    text: "zweiter Text",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }
}
