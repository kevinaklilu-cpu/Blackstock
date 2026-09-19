import XCTest
@testable import BlackstockCore

#if os(macOS)
final class LocalLoudnessAnalyzerTests: XCTestCase {
    func testFullScale997HzMonoReferenceIsMinusThreePointZeroOneLUFS() throws {
        let sampleRate = 48_000.0
        let frames = 48_000
        let samples = (0..<frames).map { index in
            Float(
                sin(
                    2 * Double.pi
                    * 997
                    * Double(index)
                    / sampleRate
                )
            )
        }

        let result = try BS1770LoudnessMeter
            .analyzePCM48k(
                interleaved: samples,
                channelCount: 1,
                inspectedAt: Date(
                    timeIntervalSince1970: 1
                )
            )

        let integrated = try XCTUnwrap(
            result.snapshot.integratedLUFS
        )
        XCTAssertEqual(
            integrated,
            -3.01,
            accuracy: 0.08
        )
        XCTAssertGreaterThan(
            result.snapshot.relativeGatedBlockCount,
            0
        )
    }

    func testDualChannelReferenceAddsAboutThreeLU() throws {
        let sampleRate = 48_000.0
        var samples: [Float] = []
        samples.reserveCapacity(48_000 * 2)

        for index in 0..<48_000 {
            let sample = Float(
                sin(
                    2 * Double.pi
                    * 997
                    * Double(index)
                    / sampleRate
                )
            )
            samples.append(sample)
            samples.append(sample)
        }

        let result = try BS1770LoudnessMeter
            .analyzePCM48k(
                interleaved: samples,
                channelCount: 2
            )

        XCTAssertEqual(
            try XCTUnwrap(
                result.snapshot.integratedLUFS
            ),
            0,
            accuracy: 0.10
        )
    }

    func testSilenceProducesNoInventedIntegratedLoudness() throws {
        let result = try BS1770LoudnessMeter
            .analyzePCM48k(
                interleaved: [Float](
                    repeating: 0,
                    count: 48_000
                ),
                channelCount: 1
            )

        XCTAssertNil(
            result.snapshot.integratedLUFS
        )
        XCTAssertNil(
            result.snapshot.truePeakDBTP
        )
        XCTAssertEqual(
            result.findings,
            [.noIntegratedLoudness]
        )
    }

    func testTruePeakFindsInterSamplePeakAboveSamplePeak() throws {
        let sampleRate = 48_000.0
        let frequency = 12_000.0
        let phase = Double.pi / 4
        let samples = (0..<4_096).map { index in
            Float(
                sin(
                    2 * Double.pi
                    * frequency
                    * Double(index)
                    / sampleRate
                    + phase
                )
            )
        }

        let result = try BS1770LoudnessMeter
            .analyzePCM48k(
                interleaved: samples,
                channelCount: 1
            )

        let samplePeak = try XCTUnwrap(
            result.snapshot.samplePeakDBFS
        )
        let truePeak = try XCTUnwrap(
            result.snapshot.truePeakDBTP
        )

        XCTAssertEqual(
            samplePeak,
            -3.0103,
            accuracy: 0.02
        )
        XCTAssertGreaterThan(
            truePeak,
            samplePeak + 2.5
        )
        XCTAssertGreaterThan(
            truePeak,
            0
        )
        XCTAssertTrue(
            result.findings.contains(
                .truePeakAboveFullScale
            )
        )
    }

    func testUnsupportedMultichannelLayoutHardStops() {
        XCTAssertThrowsError(
            try BS1770LoudnessMeter
                .analyzePCM48k(
                    interleaved: [0, 0, 0],
                    channelCount: 3
                )
        ) { error in
            XCTAssertEqual(
                error as? LocalLoudnessAnalyzerError,
                .unsupportedChannelCount(3)
            )
        }
    }
}
#endif
