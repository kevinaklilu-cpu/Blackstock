import XCTest
@testable import BlackstockCore

final class OpportunityTransparencyTests: XCTestCase {
    func testDerivedSignalsUseOnlyObservedValues() {
        let published = Date(timeIntervalSince1970: 1_000)
        let retrieved = Date(timeIntervalSince1970: 8_200) // exactly 2h later
        let metrics = YouTubeOpportunityMetrics(
            viewCount: 2_000,
            likeCount: 100,
            commentCount: 20,
            channelSubscriberCount: 1_000,
            publishedAt: published,
            retrievedAt: retrieved
        )

        XCTAssertEqual(metrics.ageHours ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(metrics.viewsPerHour ?? -1, 1_000, accuracy: 0.0001)
        XCTAssertEqual(metrics.viewsPerSubscriber ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(metrics.likeRate ?? -1, 0.05, accuracy: 0.0001)
        XCTAssertEqual(metrics.commentRate ?? -1, 0.01, accuracy: 0.0001)
        XCTAssertTrue(metrics.missingSignals.isEmpty)
    }

    func testMissingSignalsStayMissingInsteadOfBeingEstimated() {
        let metrics = YouTubeOpportunityMetrics(
            viewCount: nil,
            likeCount: nil,
            commentCount: nil,
            channelSubscriberCount: nil,
            publishedAt: nil,
            retrievedAt: Date()
        )

        XCTAssertNil(metrics.viewsPerHour)
        XCTAssertNil(metrics.viewsPerSubscriber)
        XCTAssertNil(metrics.likeRate)
        XCTAssertNil(metrics.commentRate)
        XCTAssertEqual(
            Set(metrics.missingSignals),
            Set(["Views", "Likes", "Kommentare", "Abonnentenzahl", "Veröffentlichungszeit"])
        )
    }

    func testSortingDoesNotCreateSyntheticOpportunityScore() {
        let now = Date(timeIntervalSince1970: 10_000)
        let a = candidate(
            id: "a",
            publishedAt: Date(timeIntervalSince1970: 6_400),
            views: 1_000,
            subscribers: 500,
            now: now
        )
        let b = candidate(
            id: "b",
            publishedAt: Date(timeIntervalSince1970: 8_200),
            views: 900,
            subscribers: 100,
            now: now
        )

        XCTAssertEqual([a, b].sorted(by: .views).first?.id, "a")
        XCTAssertEqual([a, b].sorted(by: .viewsPerHour).first?.id, "b")
        XCTAssertEqual([a, b].sorted(by: .channelRelative).first?.id, "b")
        XCTAssertEqual([a, b].sorted(by: .newest).first?.id, "b")
    }

    private func candidate(
        id: String,
        publishedAt: Date,
        views: Int,
        subscribers: Int,
        now: Date
    ) -> YouTubeOpportunityCandidate {
        YouTubeOpportunityCandidate(
            videoID: id,
            title: id,
            channelID: "channel-\(id)",
            channelTitle: "Channel \(id)",
            publishedAt: publishedAt,
            thumbnailURL: nil,
            query: "test",
            retrievedAt: now,
            embeddable: true,
            metrics: .init(
                viewCount: views,
                likeCount: nil,
                commentCount: nil,
                channelSubscriberCount: subscribers,
                publishedAt: publishedAt,
                retrievedAt: now
            )
        )
    }
}
