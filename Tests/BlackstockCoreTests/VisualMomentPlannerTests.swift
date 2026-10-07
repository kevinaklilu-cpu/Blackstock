import XCTest
@testable import BlackstockCore

final class VisualMomentPlannerTests: XCTestCase {
    func testStillVideoDoesNotInventHighlights() {
        XCTAssertTrue(VisualMomentPlanner.ranges(samples: (0..<100).map { .init(time: Double($0), activity: 0) },
            duration: 100, maximumDuration: 90).isEmpty)
    }
    func testSilentActionProducesBoundedDistinctRanges() {
        let samples: [VisualMomentSample] = (0..<120).map {
            .init(time: Double($0), activity: (20...27).contains($0) || (75...92).contains($0) ? 0.4 : 0.01)
        }
        let ranges = VisualMomentPlanner.ranges(samples: samples, duration: 120, maximumDuration: 90)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertTrue(ranges.allSatisfy { $0.startSeconds >= 0 && $0.endSeconds <= 120 && $0.durationSeconds >= 8 })
        XCTAssertNotEqual(ranges[0].durationSeconds, ranges[1].durationSeconds)
    }
    func testInvalidInputsAndEndOfVideoAreBounded() {
        XCTAssertTrue(VisualMomentPlanner.ranges(samples: [], duration: .infinity, maximumDuration: 90).isEmpty)
        let result = VisualMomentPlanner.ranges(samples: [.init(time: 0, activity: 0), .init(time: 19, activity: 0.8)],
            duration: 20, maximumDuration: 12)
        XCTAssertTrue(result.allSatisfy { $0.endSeconds <= 20 && $0.durationSeconds <= 12 })
    }
}
