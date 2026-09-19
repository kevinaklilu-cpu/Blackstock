import XCTest
@testable import BlackstockCore

#if os(macOS)
final class LocalAudioTechnicalInspectorTests: XCTestCase {
    func testNoAudioTrackIsAConcreteFinding() {
        let snapshot = AudioTechnicalSnapshot(
            hasAudioTrack: false,
            sampleRateHz: nil,
            channelCount: nil,
            inspectedAt: Date()
        )

        let assessment = AudioTechnicalAssessment.evaluate(snapshot)
        XCTAssertTrue(assessment.findings.contains(.noAudioTrack))
    }

    func testLowSampleRateAndMonoAreReportedWithoutSyntheticScore() {
        let snapshot = AudioTechnicalSnapshot(
            hasAudioTrack: true,
            sampleRateHz: 22_050,
            channelCount: 1,
            inspectedAt: Date()
        )

        let assessment = AudioTechnicalAssessment.evaluate(snapshot)
        XCTAssertEqual(
            Set(assessment.findings),
            Set([.lowSampleRate, .monoAudio])
        )
    }

    func testStandardStereoTechnicalSnapshotHasNoBasicFinding() {
        let snapshot = AudioTechnicalSnapshot(
            hasAudioTrack: true,
            sampleRateHz: 48_000,
            channelCount: 2,
            inspectedAt: Date()
        )

        let assessment = AudioTechnicalAssessment.evaluate(snapshot)
        XCTAssertTrue(assessment.findings.isEmpty)
    }
}
#endif
