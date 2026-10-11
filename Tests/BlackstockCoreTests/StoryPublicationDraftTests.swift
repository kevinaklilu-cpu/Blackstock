import XCTest
@testable import BlackstockCore

final class StoryPublicationDraftTests: XCTestCase {
    func testDraftUsesAllSourcesAndDoesNotCopyLeadTitle() throws {
        func source(_ id: String, _ title: String) -> YouTubeOpportunityCandidate {
            .init(videoID: id, title: title, channelID: id, channelTitle: "Channel",
                publishedAt: nil, thumbnailURL: nil, query: "", retrievedAt: Date(), embeddable: true,
                metrics: .init(viewCount: nil, likeCount: nil, commentCount: nil, publishedAt: nil, retrievedAt: Date()))
        }
        let sources = [source("abc", "Man City faces new questions"), source("def", "Man City fans react")]
        let result = try XCTUnwrap(StoryPublicationDraft.make(sources: sources, language: "de-DE",
            excerpts: ["Die Fans diskutieren den Fall."]))
        XCTAssertNotEqual(result.title, sources[0].title)
        XCTAssertTrue(result.description.contains("watch?v=abc"))
        XCTAssertTrue(result.description.contains("watch?v=def"))
        XCTAssertTrue(result.description.contains("Die Fans diskutieren den Fall."))
        XCTAssertEqual(result.alternativeTitles.count, 3)
        XCTAssertLessThanOrEqual(result.title.count, 100)
        XCTAssertNil(StoryPublicationDraft.make(sources: [sources[0]], language: "de-DE"))
    }
}
