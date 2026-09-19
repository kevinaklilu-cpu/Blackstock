import XCTest
@testable import BlackstockCore

final class StoryboardTests: XCTestCase {
    func testStoryboardNeedsAtLeastOneNamedBeatBeforeEditing() {
        var plan = StoryboardPlan(
            projectID: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertFalse(plan.isReadyForEditing)

        _ = plan.addBeat(
            title: "Hook",
            timeRange: .init(startSeconds: 0, durationSeconds: 5),
            at: Date(timeIntervalSince1970: 2)
        )

        XCTAssertTrue(plan.isReadyForEditing)
        XCTAssertEqual(plan.beats.count, 1)
        XCTAssertGreaterThan(plan.version, 1)
    }

    func testStoryboardBeatCanBeUpdatedAndRemoved() throws {
        var plan = StoryboardPlan(
            projectID: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let beat = plan.addBeat(
            title: "Hook",
            at: Date(timeIntervalSince1970: 2)
        )

        XCTAssertTrue(
            plan.updateBeat(
                id: beat.id,
                purpose: "Versprechen sofort klären",
                visualDirection: "Close-up",
                at: Date(timeIntervalSince1970: 3)
            )
        )
        let updated = try XCTUnwrap(
            plan.beats.first(where: { $0.id == beat.id })
        )
        XCTAssertEqual(
            updated.purpose,
            "Versprechen sofort klären"
        )
        XCTAssertEqual(updated.visualDirection, "Close-up")

        XCTAssertTrue(
            plan.removeBeat(
                id: beat.id,
                at: Date(timeIntervalSince1970: 4)
            )
        )
        XCTAssertTrue(plan.beats.isEmpty)
    }

    func testStoryboardReorderIsDeterministic() {
        var plan = StoryboardPlan(
            projectID: UUID(),
            updatedAt: Date()
        )
        _ = plan.addBeat(title: "A", at: Date())
        _ = plan.addBeat(title: "B", at: Date())

        XCTAssertTrue(
            plan.moveBeat(
                from: 0,
                to: 1,
                at: Date()
            )
        )
        XCTAssertEqual(plan.beats.map(\.title), ["B", "A"])
    }
}
