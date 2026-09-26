import XCTest
@testable import BlackstockCore

final class VisualEmphasisPlannerTests: XCTestCase {
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
