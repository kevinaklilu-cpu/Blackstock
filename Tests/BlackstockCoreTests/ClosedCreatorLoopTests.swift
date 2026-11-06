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
            quotaState: .unknown,
            networkAvailable: true
        )

        XCTAssertThrowsError(try context.validate()) {
            XCTAssertEqual($0 as? PublicationPreflightError, .wrongChannel)
        }
    }

    func testUnknownQuotaDoesNotPretendAvailabilityButAllowsProviderAttempt() {
        let context = PublicationPreflightContext(
            projectTargetChannelID: "channel-A",
            workspaceChannelID: "channel-A",
            authorizedUploadChannelID: "channel-A",
            renderValidated: true,
            rightsValidated: true,
            authorizationAvailable: true,
            quotaState: .unknown,
            networkAvailable: true
        )

        XCTAssertNoThrow(try context.validate())
    }

    func testKnownUnavailableQuotaHardStops() {
        let context = PublicationPreflightContext(
            projectTargetChannelID: "channel-A",
            workspaceChannelID: "channel-A",
            authorizedUploadChannelID: "channel-A",
            renderValidated: true,
            rightsValidated: true,
            authorizationAvailable: true,
            quotaState: .unavailable,
            networkAvailable: true
        )

        XCTAssertThrowsError(try context.validate()) {
            XCTAssertEqual(
                $0 as? PublicationPreflightError,
                .quotaUnavailable
            )
        }
    }

    func testResumableUploadRangeParsing() {
        XCTAssertEqual(
            YouTubeResumableUploader.nextOffset(fromRangeHeader: "bytes=0-1048575"),
            1_048_576
        )
        XCTAssertEqual(YouTubeResumableUploader.nextOffset(fromRangeHeader: nil), 0)
    }

    func testResumableStatusRequestCarriesBearerAuthorization() {
        let request = YouTubeResumableUploader.resumableStatusRequest(
            uploadURL: URL(string: "https://upload.youtube.test/session")!,
            totalSize: 1_024,
            accessToken: "access-token"
        )

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Range"),
            "bytes */1024"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Length"),
            "0"
        )
    }

    func testResumableChunkRequestCarriesBearerAuthorizationAndRange() {
        let data = Data([1, 2, 3, 4])
        let request = YouTubeResumableUploader.resumableChunkRequest(
            uploadURL: URL(string: "https://upload.youtube.test/session")!,
            mimeType: "video/mp4",
            totalSize: 10,
            offset: 4,
            data: data,
            accessToken: "access-token"
        )

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "video/mp4"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Range"),
            "bytes 4-7/10"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Length"),
            "4"
        )
        XCTAssertEqual(request.httpBody, data)
    }

    func testResumableStatusReconcilesCompletedUpload() throws {
        let data = Data(
            #"{"id":"youtube-video-complete"}"#.utf8
        )

        let status = try YouTubeResumableUploader.resumableStatus(
            statusCode: 201,
            rangeHeader: nil,
            data: data
        )

        XCTAssertEqual(
            status,
            .completed(videoID: "youtube-video-complete")
        )
    }

    func testResumableStatusDetectsExpiredSession() throws {
        let status = try YouTubeResumableUploader.resumableStatus(
            statusCode: 404,
            rangeHeader: nil,
            data: Data()
        )

        XCTAssertEqual(status, .expired)
    }

    func testResumableStatusPreservesProviderOffset() throws {
        let status = try YouTubeResumableUploader.resumableStatus(
            statusCode: 308,
            rangeHeader: "bytes=0-1048575",
            data: Data()
        )

        XCTAssertEqual(
            status,
            .incomplete(nextOffset: 1_048_576)
        )
    }

    func testUnexpectedResumableStatusDoesNotMasqueradeAsResume() {
        XCTAssertThrowsError(
            try YouTubeResumableUploader.resumableStatus(
                statusCode: 503,
                rangeHeader: nil,
                data: Data()
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeUploadError,
                .uploadFailed(503)
            )
        }
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
