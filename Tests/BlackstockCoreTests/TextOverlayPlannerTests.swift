import XCTest
@testable import BlackstockCore

final class TextOverlayPlannerTests: XCTestCase {
    func testPlannerBuildsTimedOverlayCue() {
        let operation = EditOperation(
            type: .overlay,
            timeRange: .init(
                startSeconds: 2,
                durationSeconds: 3
            ),
            value: 0.2,
            text: "Wichtiger Punkt",
            createdAt: Date()
        )

        let cues = TextOverlayPlanner().cues(
            operations: [operation],
            outputDurationSeconds: 10
        )

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Wichtiger Punkt")
        XCTAssertEqual(cues[0].startSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(cues[0].durationSeconds, 3, accuracy: 0.001)
        XCTAssertEqual(
            cues[0].normalizedYFromTop,
            0.2,
            accuracy: 0.001
        )
    }

    func testPlannerClampsOverlayAtOutputEnd() {
        let operation = EditOperation(
            type: .overlay,
            timeRange: .init(
                startSeconds: 8,
                durationSeconds: 5
            ),
            text: "Ende",
            createdAt: Date()
        )

        let cues = TextOverlayPlanner().cues(
            operations: [operation],
            outputDurationSeconds: 10
        )

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].durationSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(
            cues[0].normalizedYFromTop,
            0.18,
            accuracy: 0.001
        )
    }

    func testStructuralEditInvalidatesEarlierOverlayUntilUndo() {
        let overlay = EditOperation(
            type: .overlay,
            timeRange: .init(
                startSeconds: 1,
                durationSeconds: 2
            ),
            text: "Vorher",
            createdAt: Date()
        )
        let laterTrim = EditOperation(
            type: .trim,
            timeRange: .init(
                startSeconds: 2,
                durationSeconds: 5
            ),
            createdAt: Date()
        )

        XCTAssertTrue(
            TextOverlayPlanner().cues(
                operations: [overlay, laterTrim],
                outputDurationSeconds: 5
            ).isEmpty
        )

        let replacementOverlay = EditOperation(
            type: .overlay,
            timeRange: .init(
                startSeconds: 0.5,
                durationSeconds: 1.5
            ),
            text: "Nachher",
            createdAt: Date()
        )
        let active = TextOverlayPlanner().cues(
            operations: [
                overlay,
                laterTrim,
                replacementOverlay
            ],
            outputDurationSeconds: 5
        )
        XCTAssertEqual(active.map(\.text), ["Nachher"])
    }

    func testPlannerDropsEmptyAndInvalidOverlays() {
        let empty = EditOperation(
            type: .overlay,
            timeRange: .init(
                startSeconds: 1,
                durationSeconds: 2
            ),
            text: "   ",
            createdAt: Date()
        )
        let wrongType = EditOperation(
            type: .trim,
            timeRange: .init(
                startSeconds: 0,
                durationSeconds: 2
            ),
            text: "Kein Overlay",
            createdAt: Date()
        )

        XCTAssertTrue(
            TextOverlayPlanner().cues(
                operations: [empty, wrongType],
                outputDurationSeconds: 10
            ).isEmpty
        )
    }
}
