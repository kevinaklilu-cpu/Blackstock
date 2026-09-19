import XCTest
@testable import BlackstockCore

#if os(macOS)
final class LocalAudioSignalAnalyzerTests: XCTestCase {
    func testDBFSConversionUsesAmplitudeRatio() {
        XCTAssertEqual(
            LocalAudioSignalAnalyzer.dbfs(amplitude: 1.0) ?? 999,
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            LocalAudioSignalAnalyzer.dbfs(amplitude: 0.5) ?? 999,
            -6.0206,
            accuracy: 0.001
        )
        XCTAssertNil(LocalAudioSignalAnalyzer.dbfs(amplitude: 0))
    }

    func testFullScaleSamplesAreReportedWithoutInventedQualityScore() {
        let snapshot = AudioSignalSnapshot(
            peakDBFS: 0,
            rmsDBFS: -18,
            analyzedSampleCount: 10_000,
            fullScaleSampleCount: 3,
            inspectedAt: Date()
        )

        let assessment = AudioSignalAssessment.evaluate(snapshot)
        XCTAssertEqual(
            assessment.findings,
            [.fullScaleSamplesDetected]
        )
        XCTAssertEqual(
            snapshot.fullScaleSampleRatio ?? -1,
            0.0003,
            accuracy: 0.0000001
        )
    }

    func testNoSamplesIsExplicitlyReported() {
        let snapshot = AudioSignalSnapshot(
            peakDBFS: nil,
            rmsDBFS: nil,
            analyzedSampleCount: 0,
            fullScaleSampleCount: 0,
            inspectedAt: Date()
        )

        XCTAssertEqual(
            AudioSignalAssessment.evaluate(snapshot).findings,
            [.noSamples]
        )
    }
}
#endif
