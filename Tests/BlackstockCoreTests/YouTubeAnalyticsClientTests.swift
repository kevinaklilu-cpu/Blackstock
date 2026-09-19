import XCTest
@testable import BlackstockCore

final class YouTubeAnalyticsClientTests: XCTestCase {
    func testSnapshotRequestUsesMineVideoFilterAndBearerAuth() throws {
        let request = YouTubeAnalyticsClient(
            accessToken: "access-token",
            channelID: "channel-A"
        ).snapshotRequest(
            startDate: "2026-09-01",
            endDate: "2026-09-07",
            videoID: "video-123"
        )

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value ?? "")
            }
        )

        XCTAssertEqual(
            url.host,
            "youtubeanalytics.googleapis.com"
        )
        XCTAssertEqual(url.path, "/v2/reports")
        XCTAssertEqual(query["ids"], "channel==MINE")
        XCTAssertEqual(query["startDate"], "2026-09-01")
        XCTAssertEqual(query["endDate"], "2026-09-07")
        XCTAssertEqual(query["filters"], "video==video-123")
        XCTAssertTrue(
            query["metrics"]?.contains("averageViewDuration") == true
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer access-token"
        )
    }

    func testDecodeSnapshotPreservesProviderValuesAndTemporalContext() throws {
        let data = Data(
            """
            {
              "columnHeaders": [
                {"name":"views"},
                {"name":"engagedViews"},
                {"name":"likes"},
                {"name":"comments"},
                {"name":"shares"},
                {"name":"estimatedMinutesWatched"},
                {"name":"averageViewDuration"},
                {"name":"averageViewPercentage"},
                {"name":"subscribersGained"},
                {"name":"subscribersLost"}
              ],
              "rows": [[
                100,
                80,
                7,
                3,
                2,
                123.5,
                44.2,
                61.7,
                5,
                1
              ]]
            }
            """.utf8
        )
        let retrievedAt = Date(
            timeIntervalSince1970: 1_789_820_000
        )

        let snapshot = try YouTubeAnalyticsClient(
            accessToken: "token",
            channelID: "channel-A"
        ).decodeSnapshot(
            data,
            startDate: "2026-09-01",
            endDate: "2026-09-07",
            videoID: "video-123",
            retrievedAt: retrievedAt
        )

        XCTAssertEqual(snapshot.channelID, "channel-A")
        XCTAssertEqual(snapshot.videoID, "video-123")
        XCTAssertEqual(snapshot.startDate, "2026-09-01")
        XCTAssertEqual(snapshot.endDate, "2026-09-07")
        XCTAssertEqual(snapshot.retrievedAt, retrievedAt)
        XCTAssertEqual(snapshot.views, 100)
        XCTAssertEqual(snapshot.engagedViews, 80)
        XCTAssertEqual(snapshot.likes, 7)
        XCTAssertEqual(snapshot.comments, 3)
        XCTAssertEqual(snapshot.shares, 2)
        XCTAssertEqual(snapshot.estimatedMinutesWatched, 123.5)
        XCTAssertEqual(snapshot.averageViewDuration, 44.2)
        XCTAssertEqual(snapshot.averageViewPercentage, 61.7)
        XCTAssertEqual(snapshot.subscribersGained, 5)
        XCTAssertEqual(snapshot.subscribersLost, 1)
        XCTAssertEqual(snapshot.netSubscribers, 4)
        XCTAssertEqual(snapshot.temporalSemantic, .analyticsPeriod)
        XCTAssertEqual(snapshot.completeness, .providerMayLag)
    }

    func testMissingRowsRemainMissingInsteadOfBecomingZero() {
        let data = Data(
            """
            {
              "columnHeaders": [{"name":"views"}],
              "rows": []
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try YouTubeAnalyticsClient(
                accessToken: "token",
                channelID: "channel-A"
            ).decodeSnapshot(
                data,
                startDate: "2026-09-01",
                endDate: "2026-09-07",
                videoID: "video-123",
                retrievedAt: Date()
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeAnalyticsAPIError,
                .missingRow
            )
        }
    }

    func testMismatchedColumnsAndRowHardStop() {
        let data = Data(
            """
            {
              "columnHeaders": [
                {"name":"views"},
                {"name":"likes"}
              ],
              "rows": [[100]]
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try YouTubeAnalyticsClient(
                accessToken: "token",
                channelID: "channel-A"
            ).decodeSnapshot(
                data,
                startDate: "2026-09-01",
                endDate: "2026-09-07",
                videoID: nil,
                retrievedAt: Date()
            )
        ) {
            XCTAssertEqual(
                $0 as? YouTubeAnalyticsAPIError,
                .malformedResponse
            )
        }
    }
}
