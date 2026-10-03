import XCTest
@testable import BlackstockCore

final class StoryTopicMatcherTests: XCTestCase {
    func testRelatedSearchUsesTopicRatherThanGenericTitleWords() {
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "HIGHLIGHTS - England v Spain | Chaotic Clash"), "england spain")
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "Messi MESSI Tor 2026"), "messi tor")
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "Best new video 2026"), "")
    }
    func testChannelBrandDoesNotBecomeStoryTopic() {
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "CORE ALL SPORTS GOLF BATTLE", excluding: "CORE"), "golf battle")
        let lead = candidate("CORE ALL SPORTS GOLF BATTLE", channel: "CORE")
        XCTAssertFalse(StoryTopicMatcher().match(candidate("All Core Devs News"), to: lead).isRelated)
        XCTAssertTrue(StoryTopicMatcher().match(candidate("Final round", description: "A golf battle on the course"), to: lead).isRelated)
    }

    private func candidate(_ title: String, channel: String = "Channel", description: String? = nil) -> YouTubeOpportunityCandidate {
        .init(videoID: title, title: title, channelID: channel, channelTitle: channel,
              publishedAt: nil, thumbnailURL: nil, query: "", retrievedAt: Date(), embeddable: true,
              metrics: .init(viewCount: nil, likeCount: nil, commentCount: nil, publishedAt: nil, retrievedAt: Date()),
              description: description)
    }

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
