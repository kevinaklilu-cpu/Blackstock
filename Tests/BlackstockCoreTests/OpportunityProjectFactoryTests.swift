import XCTest
@testable import BlackstockCore

final class OpportunityProjectFactoryTests: XCTestCase {
    func testOpportunityCreatesChannelBoundProjectAndYouTubeSource() throws {
        let retrieved = Date(timeIntervalSince1970: 100)
        let candidate = YouTubeOpportunityCandidate(
            videoID: "abc123",
            title: "Testvideo",
            channelID: "source-channel",
            channelTitle: "Quelle",
            publishedAt: nil,
            thumbnailURL: nil,
            query: "test",
            retrievedAt: retrieved,
            embeddable: true,
            metrics: .init(
                viewCount: 100,
                likeCount: 10,
                commentCount: 2,
                publishedAt: nil,
                retrievedAt: retrieved
            )
        )

        let seed = try OpportunityProjectFactory().make(
            opportunity: candidate,
            targetChannelID: "target-channel",
            strategyVersion: 3,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(seed.project.targetChannelID, "target-channel")
        XCTAssertEqual(seed.project.strategyVersion, 3)
        XCTAssertEqual(seed.project.stage, .research)
        XCTAssertEqual(seed.source.provider, .youtube)
        XCTAssertEqual(seed.source.externalID, "abc123")
        XCTAssertEqual(
            seed.source.pageURL.absoluteString,
            "https://www.youtube.com/watch?v=abc123"
        )
        XCTAssertEqual(seed.opportunityID, candidate.id)
    }


    func testClipProjectCanStartDirectlyInProduction() throws {
        let candidate = YouTubeOpportunityCandidate(
            videoID: "clip123",
            title: "Clip source",
            channelID: "source-channel",
            channelTitle: "Quelle",
            publishedAt: nil,
            thumbnailURL: nil,
            query: "test",
            retrievedAt: Date(timeIntervalSince1970: 100),
            embeddable: true,
            metrics: .init(
                viewCount: nil,
                likeCount: nil,
                commentCount: nil,
                publishedAt: nil,
                retrievedAt: Date(timeIntervalSince1970: 100)
            )
        )

        let seed = try OpportunityProjectFactory().make(
            opportunity: candidate,
            targetChannelID: "target-channel",
            strategyVersion: 1,
            initialStage: .production
        )

        XCTAssertEqual(seed.project.stage, .production)
    }

    func testMissingTargetChannelHardFailsProjectCreation() {
        let candidate = YouTubeOpportunityCandidate(
            videoID: "abc",
            title: "Test",
            channelID: "source",
            channelTitle: "Source",
            publishedAt: nil,
            thumbnailURL: nil,
            query: "test",
            retrievedAt: Date(),
            embeddable: true,
            metrics: .init(
                viewCount: nil,
                likeCount: nil,
                commentCount: nil,
                publishedAt: nil,
                retrievedAt: Date()
            )
        )

        XCTAssertThrowsError(
            try OpportunityProjectFactory().make(
                opportunity: candidate,
                targetChannelID: " ",
                strategyVersion: 1
            )
        ) {
            XCTAssertEqual(
                $0 as? OpportunityProjectFactoryError,
                .missingTargetChannel
            )
        }
    }
}
