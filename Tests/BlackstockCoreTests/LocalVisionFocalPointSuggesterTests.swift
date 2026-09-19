import XCTest
@testable import BlackstockCore

#if os(macOS)
final class LocalVisionFocalPointSuggesterTests: XCTestCase {
    func testAggregateUsesWeightedObservationCenter() throws {
        let observations = [
            VisionFocalObservation(
                normalizedX: 0.25,
                normalizedYFromTop: 0.40,
                weight: 1,
                kind: .human
            ),
            VisionFocalObservation(
                normalizedX: 0.75,
                normalizedYFromTop: 0.60,
                weight: 3,
                kind: .face
            )
        ]

        let proposal = try XCTUnwrap(
            LocalVisionFocalPointSuggester.aggregate(
                observations,
                sampledFrameCount: 5,
                now: Date(timeIntervalSince1970: 10)
            )
        )

        XCTAssertEqual(proposal.focalX, 0.625, accuracy: 0.0001)
        XCTAssertEqual(proposal.focalY, 0.55, accuracy: 0.0001)
        XCTAssertEqual(proposal.faceObservationCount, 1)
        XCTAssertEqual(proposal.humanObservationCount, 1)
        XCTAssertEqual(proposal.observationCount, 2)
        XCTAssertEqual(proposal.sampledFrameCount, 5)
    }

    func testAggregateNeedsRealObservation() {
        XCTAssertNil(
            LocalVisionFocalPointSuggester.aggregate(
                [],
                sampledFrameCount: 7,
                now: Date()
            )
        )
    }

    func testObservationCoordinatesAreClamped() {
        let observation = VisionFocalObservation(
            normalizedX: 2,
            normalizedYFromTop: -1,
            weight: 0,
            kind: .face
        )

        XCTAssertEqual(observation.normalizedX, 1)
        XCTAssertEqual(observation.normalizedYFromTop, 0)
        XCTAssertGreaterThan(observation.weight, 0)
    }
}
#endif
