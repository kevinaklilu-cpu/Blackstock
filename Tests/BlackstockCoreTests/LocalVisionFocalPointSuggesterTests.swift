import XCTest
@testable import BlackstockCore

#if os(macOS)
final class LocalVisionFocalPointSuggesterTests: XCTestCase {
    func testSamplingUsesSelectedClipInsteadOfEntireMovie() {
        let times = LocalVisionFocalPointSuggester.sampleTimes(duration: 1304,
            sourceRange: .init(startSeconds: 629.5, durationSeconds: 45))
        XCTAssertEqual(times.count, 7)
        XCTAssertTrue(times.allSatisfy { $0 > 629.5 && $0 < 674.5 })
        XCTAssertEqual(times[3], 652, accuracy: 0.0001)
    }

    func testSamplingClampsToAvailableMediaAndRejectsEmptyRange() {
        XCTAssertTrue(LocalVisionFocalPointSuggester.sampleTimes(duration: 100,
            sourceRange: .init(startSeconds: 101, durationSeconds: 4)).isEmpty)
        XCTAssertTrue(LocalVisionFocalPointSuggester.sampleTimes(duration: 100,
            sourceRange: .init(startSeconds: 98, durationSeconds: 45)).allSatisfy { $0 > 98 && $0 < 100 })
    }

    func testClipFramingSurvivesRenamingAndArtifactUpdates() throws {
        let framing = ReframeSpec(aspectRatio: .portrait9x16, focalX: 0.8, focalY: 0.3)
        let clip = SavedClipSelection(sourceRange: .init(startSeconds: 10, durationSeconds: 45),
            transcriptPreview: "", wordCount: 0, reframeSpec: framing, savedAt: Date())
        let copy = clip.withTitle("Changed").withRenderArtifact(nil)
        let restored = try JSONDecoder().decode(SavedClipSelection.self, from: JSONEncoder().encode(copy))
        XCTAssertEqual(restored.reframeSpec, framing)
        XCTAssertEqual(restored.sourceRange, clip.sourceRange)
    }

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
