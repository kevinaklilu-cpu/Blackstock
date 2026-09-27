import XCTest
@testable import BlackstockCore

final class StoryTopicMatcherTests: XCTestCase {
    func testGenericVideoWordsDoNotMakeTopicsRelated() {
        XCTAssertFalse(StoryTopicMatcher().match("Best football highlights 2026", to: "Best cooking video 2026").isRelated)
    }

    func testTopicEvidenceIsNormalizedAndExplainable() {
        let match = StoryTopicMatcher().match("MESSI erzielt Tor", to: "Messi: Interview nach Spiel")
        XCTAssertEqual(match.terms, ["messi"])
        XCTAssertTrue(match.explanation.contains("messi"))
    }

    #if os(macOS)
    func testSceneSelectionFindsLaterRelevantSpeech() {
        let transcript = LocalTranscript(localeIdentifier: "de-DE", text: "",
            segments: [
                .init(startSeconds: 0, durationSeconds: 2, text: "Willkommen heute", confidence: 1),
                .init(startSeconds: 20, durationSeconds: 2, text: "Messi erzielt ein Tor", confidence: 1)
            ], onDevice: true, createdAt: Date())
        let selected = StorySceneSelector().select(transcript: transcript, reference: "Messi im Finale",
            sourceDuration: 30, maximumDuration: 5)
        XCTAssertEqual(selected?.range.startSeconds ?? 0, 19.9, accuracy: 0.001)
        XCTAssertLessThanOrEqual(selected?.range.durationSeconds ?? 100, 5)
        XCTAssertNil(StorySceneSelector().select(transcript: transcript, reference: "Kuchen backen",
            sourceDuration: 30, maximumDuration: 5))
    }
    #endif

    func testOldSettingsDecodeWithoutExplanation() throws {
        let id = UUID()
        let json = "{\"captureID\":\"\(id)\",\"enabled\":true,\"timelineStartSeconds\":0,\"sourceStartSeconds\":0,\"durationSeconds\":5}"
        let setting = try JSONDecoder().decode(SupplementalVideoInsertSetting.self, from: Data(json.utf8))
        XCTAssertNil(setting.selectionExplanation)
        XCTAssertEqual(setting.captureID, id)
    }
}
