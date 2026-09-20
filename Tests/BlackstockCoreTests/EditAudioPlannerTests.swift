import XCTest
@testable import BlackstockCore

final class EditAudioPlannerTests: XCTestCase {
    func testDefaultMasterVolumeIsUnity() {
        XCTAssertEqual(
            EditAudioPlanner().masterVolume(operations: []),
            1
        )
    }

    func testLatestVolumeOperationWins() {
        let operations = [
            EditOperation(
                type: .volume,
                value: 0.8,
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            EditOperation(
                type: .trim,
                timeRange: EditTimeRange(
                    startSeconds: 0,
                    durationSeconds: 10
                ),
                createdAt: Date(timeIntervalSince1970: 2)
            ),
            EditOperation(
                type: .volume,
                value: 0.35,
                createdAt: Date(timeIntervalSince1970: 3)
            )
        ]

        XCTAssertEqual(
            EditAudioPlanner().masterVolume(
                operations: operations
            ),
            0.35,
            accuracy: 0.0001
        )
    }

    func testMasterVolumeIsClamped() {
        XCTAssertEqual(
            EditAudioPlanner().masterVolume(
                operations: [
                    EditOperation(
                        type: .volume,
                        value: 2,
                        createdAt: Date()
                    )
                ]
            ),
            1
        )

        XCTAssertEqual(
            EditAudioPlanner().masterVolume(
                operations: [
                    EditOperation(
                        type: .volume,
                        value: -1,
                        createdAt: Date()
                    )
                ]
            ),
            0
        )
    }
}
