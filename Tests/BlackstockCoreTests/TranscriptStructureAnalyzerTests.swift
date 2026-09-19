import XCTest
@testable import BlackstockCore

final class TranscriptStructureAnalyzerTests: XCTestCase {
    func testAnalyzerReportsOnlyMeasuredStructureFacts() {
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "Hallo Welt das ist ein Test",
            segments: [
                .init(
                    startSeconds: 1,
                    durationSeconds: 1,
                    text: "Hallo Welt",
                    confidence: 0.9
                ),
                .init(
                    startSeconds: 4.5,
                    durationSeconds: 1.5,
                    text: "das ist ein Test",
                    confidence: 0.9
                )
            ],
            onDevice: true,
            createdAt: Date()
        )

        let snapshot = TranscriptStructureAnalyzer().analyze(
            transcript: transcript,
            now: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(snapshot.firstSpeechStartSeconds, 1)
        XCTAssertEqual(snapshot.spokenDurationSeconds, 2.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.longestInterSegmentGapSeconds ?? -1, 2.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.gapsAtLeastTwoSeconds, 1)
        XCTAssertEqual(snapshot.wordsInFirstThirtySeconds, 6)
        XCTAssertEqual(snapshot.totalWordCount, 6)
        XCTAssertEqual(snapshot.segmentCount, 2)
    }

    func testEmptyTranscriptDoesNotInventTiming() {
        let transcript = LocalTranscript(
            localeIdentifier: "de-DE",
            text: "",
            segments: [],
            onDevice: true,
            createdAt: Date()
        )

        let snapshot = TranscriptStructureAnalyzer().analyze(
            transcript: transcript
        )

        XCTAssertNil(snapshot.firstSpeechStartSeconds)
        XCTAssertNil(snapshot.longestInterSegmentGapSeconds)
        XCTAssertEqual(snapshot.spokenDurationSeconds, 0)
        XCTAssertEqual(snapshot.totalWordCount, 0)
    }
}
