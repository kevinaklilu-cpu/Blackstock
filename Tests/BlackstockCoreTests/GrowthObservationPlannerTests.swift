import XCTest
@testable import BlackstockCore

final class GrowthObservationPlannerTests: XCTestCase {
    func testTwentyFourHourWindowBecomesDueOnlyAfterElapsedTime() {
        let publishedAt = Date(timeIntervalSince1970: 1_000_000)
        let record = PublishedVideoRecord(
            projectID: UUID(),
            experimentID: nil,
            targetChannelID: "channel",
            youtubeVideoID: "video",
            publishedAt: publishedAt
        )

        let before = GrowthObservationPlanner().duePlans(
            for: record,
            now: publishedAt.addingTimeInterval(23 * 60 * 60)
        )
        let after = GrowthObservationPlanner().duePlans(
            for: record,
            now: publishedAt.addingTimeInterval(25 * 60 * 60)
        )

        XCTAssertFalse(before.contains { $0.window == .first24Hours })
        XCTAssertTrue(after.contains { $0.window == .first24Hours })
    }

    func testAlreadyCollectedWindowIsNotDueAgain() {
        let publishedAt = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = YouTubeAnalyticsSnapshot(
            channelID: "channel",
            videoID: "video",
            startDate: "1970-01-12",
            endDate: "1970-01-13",
            retrievedAt: Date(),
            views: 100,
            engagedViews: nil,
            likes: nil,
            comments: nil,
            shares: nil,
            estimatedMinutesWatched: nil,
            averageViewDuration: nil,
            averageViewPercentage: nil,
            subscribersGained: nil,
            subscribersLost: nil
        )
        let observation = GrowthObservation(
            window: .first24Hours,
            analytics: snapshot,
            collectedAt: Date()
        )
        let record = PublishedVideoRecord(
            projectID: UUID(),
            experimentID: nil,
            targetChannelID: "channel",
            youtubeVideoID: "video",
            publishedAt: publishedAt,
            observations: [observation]
        )

        let due = GrowthObservationPlanner().duePlans(
            for: record,
            now: publishedAt.addingTimeInterval(80 * 60 * 60)
        )

        XCTAssertFalse(due.contains { $0.window == .first24Hours })
        XCTAssertTrue(due.contains { $0.window == .first72Hours })
    }

    func testAnalyticsPeriodIsExplicitlyPacificCalendarDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = utc.date(
            from: DateComponents(
                year: 2026,
                month: 9,
                day: 19,
                hour: 6,
                minute: 30
            )
        )!

        XCTAssertEqual(
            GrowthObservationPlanner.analyticsDateString(date),
            "2026-09-18"
        )
    }

    func testPlannerUsesAnalyticsPeriodSemantic() {
        let publishedAt = Date(timeIntervalSince1970: 1_000_000)
        let record = PublishedVideoRecord(
            projectID: UUID(),
            experimentID: nil,
            targetChannelID: "channel",
            youtubeVideoID: "video",
            publishedAt: publishedAt
        )

        let plan = GrowthObservationPlanner().plans(
            for: record,
            now: publishedAt
        ).first

        XCTAssertEqual(plan?.temporalSemantic, .analyticsPeriod)
    }
    func testGrowthWindowLabelsDoNotChangeCanonicalRawValues() {
        XCTAssertEqual(
            GrowthObservationWindow.first24Hours.rawValue,
            "FIRST_24_HOURS"
        )
        XCTAssertEqual(
            GrowthObservationWindow.first24Hours.germanTitle,
            "24 Std."
        )
        XCTAssertEqual(
            GrowthObservationWindow.first28Days.rawValue,
            "FIRST_28_DAYS"
        )
        XCTAssertEqual(
            GrowthObservationWindow.first28Days.germanTitle,
            "28 Tage"
        )
    }

    func testAnalyticsSnapshotRemainsExplicitAnalyticsPeriodWithLagWarning() {
        let snapshot = YouTubeAnalyticsSnapshot(
            channelID: "channel",
            videoID: "video",
            startDate: "2026-09-01",
            endDate: "2026-09-07",
            retrievedAt: Date(),
            views: 10,
            engagedViews: nil,
            likes: nil,
            comments: nil,
            shares: nil,
            estimatedMinutesWatched: nil,
            averageViewDuration: nil,
            averageViewPercentage: nil,
            subscribersGained: nil,
            subscribersLost: nil
        )

        XCTAssertEqual(
            snapshot.temporalSemantic,
            .analyticsPeriod
        )
        XCTAssertEqual(
            snapshot.completeness,
            .providerMayLag
        )
        XCTAssertEqual(
            snapshot.requestedStartDate,
            "2026-09-01"
        )
        XCTAssertEqual(
            snapshot.requestedEndDate,
            "2026-09-07"
        )
    }

}
