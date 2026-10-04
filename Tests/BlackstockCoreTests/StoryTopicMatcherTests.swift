import XCTest
@testable import BlackstockCore

final class StoryTopicMatcherTests: XCTestCase {
    func testRelatedSearchUsesTopicRatherThanGenericTitleWords() {
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "HIGHLIGHTS - England v Spain | Chaotic Clash"), "england spain")
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "Messi MESSI Tor 2026"), "messi tor")
        XCTAssertEqual(StoryTopicMatcher().searchQuery(for: "Best new video 2026"), "")
    }
    func testGenericSelectionWordsDoNotSuggestGamingForFootball() {
        let matcher = StoryTopicMatcher()
        let lead = candidate("Picking The World's BEST Wonderkid In EVERY Position! | Saturday Social")
        XCTAssertFalse(matcher.match(candidate("ULTIMATE TBC Classic Class Picking Guide | World of Warcraft"), to: lead).isRelated)
        XCTAssertTrue(matcher.match(candidate("Picking the BEST WONDERKID in WORLD FOOTBALL"), to: lead).isRelated)
        XCTAssertEqual(matcher.searchQuery(for: lead.title), "wonderkid position")
    }

    func testGrandDoesNotConnectDifferentSports() {
        let matcher = StoryTopicMatcher()
        let lead = candidate("Qualifying Highlights | 2026 Bahrain Grand Prix in Malaysia", channel: "FORMULA 1")
        XCTAssertFalse(matcher.match(candidate("Grand Final Highlights | Warrington Wolves v WakeField Trinity | Betfred Super League"), to: lead).isRelated)
        XCTAssertTrue(matcher.match(candidate("Russell reacts to Bahrain qualifying"), to: lead).isRelated)
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
