import XCTest
@testable import BlackstockCore

#if os(macOS)
final class LocalOnDeviceTranscriptionTests: XCTestCase {
    func testWebVTTWriterUsesTranscriptSegmentTiming() {
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Hallo Welt",
            segments: [
                .init(
                    startSeconds: 1.25,
                    durationSeconds: 0.5,
                    text: "Hallo",
                    confidence: 0.9
                ),
                .init(
                    startSeconds: 1.8,
                    durationSeconds: 0.7,
                    text: "Welt",
                    confidence: 0.8
                )
            ],
            onDevice: true,
            createdAt: Date()
        )

        let contents = WebVTTCaptionWriter().contents(for: transcript)

        XCTAssertTrue(contents.hasPrefix("WEBVTT"))
        XCTAssertTrue(contents.contains("00:00:01.250 --> 00:00:01.750"))
        XCTAssertTrue(contents.contains("Hallo"))
        XCTAssertTrue(contents.contains("00:00:01.800 --> 00:00:02.500"))
        XCTAssertTrue(contents.contains("Welt"))
    }

    func testTimestampNeverGoesNegative() {
        XCTAssertEqual(
            WebVTTCaptionWriter.timestamp(-1),
            "00:00:00.000"
        )
    }
}
#endif
