import XCTest
@testable import BlackstockCore

final class CreatorProvidedSourceTests: XCTestCase {
    private func candidate(
        description: String?
    ) -> YouTubeOpportunityCandidate {
        YouTubeOpportunityCandidate(
            videoID: "video-123",
            title: "Test Video",
            channelID: "channel-123",
            channelTitle: "Creator",
            publishedAt: nil,
            thumbnailURL: nil,
            query: "test",
            retrievedAt: Date(timeIntervalSince1970: 1_700_000_000),
            embeddable: true,
            contentKind: .video,
            durationSeconds: 420,
            description: description,
            metrics: YouTubeOpportunityMetrics(
                viewCount: 10,
                likeCount: 2,
                commentCount: 1,
                publishedAt: nil,
                retrievedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }

    func testCreatorDirectMediaLinksAreDetected() {
        let item = candidate(
            description:
                "Original: https://cdn.creator.example/video-123.mp4\nMehr Infos: https://creator.example/post"
        )

        XCTAssertEqual(
            item.creatorProvidedSourceURLs,
            [
                URL(
                    string:
                        "https://cdn.creator.example/video-123.mp4"
                )!
            ]
        )
    }

    func testYouTubeAndOrdinaryWebLinksAreNotDownloadSources() {
        let item = candidate(
            description:
                "https://youtu.be/video-123 https://www.youtube.com/watch?v=video-123 https://creator.example/page"
        )

        XCTAssertTrue(
            item.creatorProvidedSourceURLs.isEmpty
        )
    }

    func testProjectPersistsCreatorProvidedSourceLink() throws {
        let item = candidate(
            description:
                "Download: https://media.creator.example/master.mov"
        )

        let seed = try OpportunityProjectFactory().make(
            opportunity: item,
            targetChannelID: "target-channel",
            strategyVersion: 1
        )

        XCTAssertEqual(
            seed.source.creatorProvidedSourceURLs,
            [
                URL(
                    string:
                        "https://media.creator.example/master.mov"
                )!
            ]
        )
    }

    func testUnsupportedMediaExtensionsAreIgnored() {
        let item = candidate(
            description:
                "Audio: https://media.creator.example/audio.mp3 Video page: https://media.creator.example/watch"
        )

        XCTAssertTrue(
            item.creatorProvidedSourceURLs.isEmpty
        )
    }
}
