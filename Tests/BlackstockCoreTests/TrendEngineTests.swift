import XCTest
@testable import BlackstockCore

final class TrendEngineTests: XCTestCase {
    func testFastFreshVideoRanksAheadOfSlowOldVideo() {
        let now = Date()
        let fast = VideoMetric(id: "fast", title: "Swift Video Editing", channelID: "a", channelTitle: "A", publishedAt: now.addingTimeInterval(-3600), durationSeconds: 600, viewCount: 50_000, likeCount: 4_000, commentCount: 300, tags: ["Swift", "Video"])
        let slow = VideoMetric(id: "slow", title: "Old Topic", channelID: "b", channelTitle: "B", publishedAt: now.addingTimeInterval(-7 * 86400), durationSeconds: 600, viewCount: 55_000, likeCount: 1_000, commentCount: 50, tags: ["Other"])
        let channel = ChannelSnapshot(id: "me", title: "Me", medianViews: 10_000, medianViewsPerHour: 200, recentTopics: ["Swift", "Video"])
        let ranked = TrendEngine().rank(videos: [slow, fast], channel: channel)
        XCTAssertEqual(ranked.first?.video.id, "fast")
        XCTAssertFalse(ranked.first?.reasons.isEmpty ?? true)
    }

    func testNoVisibleScoreConceptInReasons() {
        let video = VideoMetric(id: "x", title: "Editing", channelID: "a", channelTitle: "A", publishedAt: Date(), durationSeconds: 120, viewCount: 1000)
        let signal = TrendEngine().rank(videos: [video], channel: nil)[0]
        XCTAssertFalse(signal.reasons.contains { $0.label.lowercased().contains("score") || $0.label.lowercased().contains("chance") })
    }

    func testLongSourceCanRecommendShortRepurpose() {
        let now = Date()
        let source = VideoMetric(id: "source", title: "Deep Editing Tutorial", channelID: "a", channelTitle: "A", publishedAt: now.addingTimeInterval(-1800), durationSeconds: 900, viewCount: 100_000, likeCount: 5_000)
        let baseline = VideoMetric(id: "base", title: "Baseline", channelID: "b", channelTitle: "B", publishedAt: now.addingTimeInterval(-3600), durationSeconds: 500, viewCount: 3_000)
        let ranked = TrendEngine().rank(videos: [source, baseline], channel: nil)
        XCTAssertEqual(ranked.first(where: { $0.video.id == "source" })?.recommendedFormat, .short)
    }

    func testDurationFiltersCoverLongTailWithoutGaps() {
        XCTAssertTrue(VideoDurationFilter.upToOne.contains(seconds: 59))
        XCTAssertTrue(VideoDurationFilter.oneToFour.contains(seconds: 60))
        XCTAssertTrue(VideoDurationFilter.oneToFour.contains(seconds: 239))
        XCTAssertTrue(VideoDurationFilter.fourToTen.contains(seconds: 240))
        XCTAssertTrue(VideoDurationFilter.tenToTwenty.contains(seconds: 600))
        XCTAssertTrue(VideoDurationFilter.twentyToSixty.contains(seconds: 1200))
        XCTAssertTrue(VideoDurationFilter.overSixty.contains(seconds: 3600))
    }
}
