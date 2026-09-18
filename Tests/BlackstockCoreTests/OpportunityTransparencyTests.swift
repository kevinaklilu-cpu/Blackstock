import XCTest
@testable import BlackstockCore

final class OpportunityTransparencyTests: XCTestCase {
    func testMissingYouTubeSignalsStayMissingInsteadOfBeingEstimated() {
        let metrics = YouTubeOpportunityMetrics(
            viewCount: nil,
            likeCount: nil,
            commentCount: nil,
            publishedAt: nil,
            retrievedAt: Date()
        )

        XCTAssertEqual(
            Set(metrics.missingSignals),
            Set(["Views", "Likes", "Kommentare", "Veröffentlichungszeit"])
        )
    }

    func testOpportunityOrderingUsesOfficialYouTubeOrderParameters() {
        XCTAssertEqual(OpportunitySortMode.relevance.youtubeOrderParameter, "relevance")
        XCTAssertEqual(OpportunitySortMode.newest.youtubeOrderParameter, "date")
        XCTAssertEqual(OpportunitySortMode.views.youtubeOrderParameter, "viewCount")
    }

    func testRawMetricsRemainRawValues() {
        let published = Date(timeIntervalSince1970: 1_000)
        let retrieved = Date(timeIntervalSince1970: 8_200)
        let metrics = YouTubeOpportunityMetrics(
            viewCount: 2_000,
            likeCount: 100,
            commentCount: 20,
            publishedAt: published,
            retrievedAt: retrieved
        )

        XCTAssertEqual(metrics.viewCount, 2_000)
        XCTAssertEqual(metrics.likeCount, 100)
        XCTAssertEqual(metrics.commentCount, 20)
        XCTAssertEqual(metrics.publishedAt, published)
        XCTAssertEqual(metrics.retrievedAt, retrieved)
    }
}
