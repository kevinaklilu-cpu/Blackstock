import XCTest
@testable import BlackstockCore

final class GrowthAnalyticsContextGuardTests: XCTestCase {
    func testPublishedRecordMatchingProjectPasses() throws {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .published,
            strategyVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let record = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-A",
            publishedAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertNoThrow(
            try GrowthAnalyticsContextGuard().validate(
                project: project,
                record: record
            )
        )
    }

    func testWrongChannelIsRejected() {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .published,
            strategyVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let record = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-B",
            youtubeVideoID: "video-A",
            publishedAt: Date()
        )

        XCTAssertThrowsError(
            try GrowthAnalyticsContextGuard().validate(
                project: project,
                record: record
            )
        ) {
            XCTAssertEqual(
                $0 as? GrowthAnalyticsContextError,
                .channelMismatch
            )
        }
    }

    func testWrongProjectIsRejected() {
        let project = BlackstockProject(
            id: UUID(),
            title: "Video",
            targetChannelID: "channel-A",
            stage: .published,
            strategyVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let record = PublishedVideoRecord(
            projectID: UUID(),
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "video-A",
            publishedAt: Date()
        )

        XCTAssertThrowsError(
            try GrowthAnalyticsContextGuard().validate(
                project: project,
                record: record
            )
        ) {
            XCTAssertEqual(
                $0 as? GrowthAnalyticsContextError,
                .projectMismatch
            )
        }
    }

    func testMissingVideoIDIsRejected() {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .published,
            strategyVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let record = PublishedVideoRecord(
            projectID: projectID,
            experimentID: nil,
            targetChannelID: "channel-A",
            youtubeVideoID: "   ",
            publishedAt: Date()
        )

        XCTAssertThrowsError(
            try GrowthAnalyticsContextGuard().validate(
                project: project,
                record: record
            )
        ) {
            XCTAssertEqual(
                $0 as? GrowthAnalyticsContextError,
                .missingVideoID
            )
        }
    }
}
