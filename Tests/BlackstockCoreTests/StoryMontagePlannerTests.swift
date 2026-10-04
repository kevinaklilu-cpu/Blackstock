import XCTest
@testable import BlackstockCore

final class StoryMontagePlannerTests: XCTestCase {
    func testDistributedScenesPreserveCoverageAndSourceOrder() {
        let a = UUID(), b = UUID()
        let inputs = [a,b].map { SupplementalVideoInsertInput(captureID: $0,
            fileURL: URL(fileURLWithPath: "/tmp/fixture"), timelineStartSeconds: 0,
            sourceStartSeconds: 10, durationSeconds: 18) }
        let result = StoryMontagePlanner.distribute(inputs, outputDuration: 60)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.map(\.captureID), [a,b,a,b,a,b])
        XCTAssertEqual(result.reduce(0) { $0 + $1.durationSeconds }, 36, accuracy: 0.001)
        XCTAssertTrue(zip(result, result.dropFirst()).allSatisfy {
            $0.timelineStartSeconds + $0.durationSeconds <= $1.timelineStartSeconds
        })
        XCTAssertEqual(result.filter { $0.captureID == a }.map(\.sourceStartSeconds), [10,16,22])
        XCTAssertGreaterThan(result.first!.timelineStartSeconds, 0)
        XCTAssertLessThan(result.last!.timelineStartSeconds + result.last!.durationSeconds, 60)
    }

    func testInvalidAndOverlongCoverageIsRejected() {
        let input = SupplementalVideoInsertInput(captureID: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a"),
            timelineStartSeconds: 0, sourceStartSeconds: 0, durationSeconds: 20)
        XCTAssertTrue(StoryMontagePlanner.distribute([input], outputDuration: 10).isEmpty)
        XCTAssertTrue(StoryMontagePlanner.distribute([input], outputDuration: .nan).isEmpty)
    }
}
