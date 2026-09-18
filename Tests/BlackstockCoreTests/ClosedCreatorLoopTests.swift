import XCTest
@testable import BlackstockCore

final class ClosedCreatorLoopTests: XCTestCase {
    func testWrongChannelStopsPublishingBeforeRemoteAction() {
        let context = PublicationPreflightContext(
            projectTargetChannelID: "channel-A",
            workspaceChannelID: "channel-A",
            authorizedUploadChannelID: "channel-B",
            renderValidated: true,
            rightsValidated: true,
            authorizationAvailable: true,
            quotaAvailable: true,
            networkAvailable: true
        )

        XCTAssertThrowsError(try context.validate()) {
            XCTAssertEqual($0 as? PublicationPreflightError, .wrongChannel)
        }
    }

    func testResumableUploadRangeParsing() {
        XCTAssertEqual(
            YouTubeResumableUploader.nextOffset(fromRangeHeader: "bytes=0-1048575"),
            1_048_576
        )
        XCTAssertEqual(YouTubeResumableUploader.nextOffset(fromRangeHeader: nil), 0)
    }

    func testUploadResponseExtractsRealYouTubeVideoID() {
        let data = Data(#"{"id":"youtube-video-123","kind":"youtube#video"}"#.utf8)
        XCTAssertEqual(
            YouTubeResumableUploader.videoID(from: data),
            "youtube-video-123"
        )
    }

    func testGrowthLearningContainsOnlyObservedAnalyticsFacts() {
        let snapshot = YouTubeAnalyticsSnapshot(
            channelID: "channel-A",
            videoID: "video-1",
            startDate: "2026-09-01",
            endDate: "2026-09-07",
            retrievedAt: Date(timeIntervalSince1970: 10),
            views: 1_000,
            engagedViews: 900,
            likes: 100,
            comments: 20,
            shares: 5,
            estimatedMinutesWatched: 2_500,
            averageViewDuration: 150,
            averageViewPercentage: 62.5,
            subscribersGained: 12,
            subscribersLost: 2
        )
        let observation = GrowthObservation(
            window: .first7Days,
            analytics: snapshot,
            collectedAt: Date(timeIntervalSince1970: 10)
        )
        let published = PublishedVideoRecord(
            projectID: UUID(),
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-1",
            publishedAt: Date(timeIntervalSince1970: 1),
            observations: [observation]
        )

        let learning = GrowthLearningEngine().summarize(published)
        XCTAssertNotNil(learning)
        XCTAssertTrue(learning?.facts.contains(where: { $0.contains("1000 Views") }) == true)
        XCTAssertTrue(learning?.facts.contains(where: { $0.contains("12 gewonnene Abonnenten") }) == true)
        XCTAssertFalse(learning?.facts.contains(where: { $0.lowercased().contains("garant") }) == true)
    }

    func testProjectFollowsCanonicalStageOrder() {
        var project = BlackstockProject(
            title: "Test",
            targetChannelID: "channel-A",
            stage: .production,
            strategyVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertTrue(project.advance(to: .preview, at: Date(timeIntervalSince1970: 2)))
        XCTAssertFalse(project.advance(to: .publishing, at: Date(timeIntervalSince1970: 3)))
        XCTAssertEqual(project.stage, .preview)
    }
}
