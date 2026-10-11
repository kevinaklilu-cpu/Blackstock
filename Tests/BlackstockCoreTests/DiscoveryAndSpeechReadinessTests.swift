import XCTest
@testable import BlackstockCore

final class DiscoveryAndSpeechReadinessTests: XCTestCase {
    private func video(_ id: String) -> YouTubeOpportunityCandidate {
        .init(videoID: id, title: id, channelID: "channel", channelTitle: "Channel", publishedAt: nil,
              thumbnailURL: nil, query: "", retrievedAt: Date(), embeddable: true,
              metrics: .init(viewCount: nil, likeCount: nil, commentCount: nil, publishedAt: nil, retrievedAt: Date()))
    }

    func testElevenResultsDoNotPreventLoadingLaterPages() {
        var feed = OpportunityPageAccumulator(existingIDs: [])
        feed.append(.init(candidates: (0..<11).map { video("v\($0)") }, nextPageToken: "page2"))
        XCTAssertTrue(feed.needsMore())
        feed.append(.init(candidates: (11..<61).map { video("v\($0)") }, nextPageToken: "page3"))
        XCTAssertEqual(feed.candidates.count, 61)
        XCTAssertFalse(feed.needsMore())
        XCTAssertEqual(feed.nextPageToken, "page3")
    }

    func testDuplicatesAndFilteredEmptyPagesDoNotEndFeed() {
        var feed = OpportunityPageAccumulator(existingIDs: ["existing"], initialToken: "p2")
        feed.append(.init(candidates: [video("existing"), video("new"), video("new")], nextPageToken: "p3"))
        feed.append(.init(candidates: [], nextPageToken: "p4"))
        XCTAssertEqual(feed.candidates.map(\.videoID), ["new"])
        XCTAssertTrue(feed.needsMore())
        XCTAssertEqual(feed.nextPageToken, "p4")
    }

    func testCursorCycleStopsWithoutDroppingResults() {
        var feed = OpportunityPageAccumulator(existingIDs: [], initialToken: "p2")
        feed.append(.init(candidates: [video("one")], nextPageToken: "p3"))
        feed.append(.init(candidates: [video("two")], nextPageToken: "p2"))
        XCTAssertNil(feed.nextPageToken)
        XCTAssertEqual(feed.candidates.count, 2)
    }

    func testAllPagesRemainAccessibleBeyondFirstHundred() {
        var existing: [String] = []
        var token: String? = nil
        for page in 0..<8 {
            var feed = OpportunityPageAccumulator(existingIDs: existing, initialToken: token)
            feed.append(.init(candidates: (0..<50).map { video("\(page)-\($0)") }, nextPageToken: "p\(page+1)"))
            existing += feed.candidates.map(\.videoID)
            token = feed.nextPageToken
        }
        XCTAssertEqual(existing.count, 400)
        XCTAssertNotNil(token)
    }

    func testLongSpeechPlanCoversWholeSourceWithShortRequests() {
        let chunks = SpeechAnalysisChunk.plan(duration: 10800)
        XCTAssertEqual(chunks.first?.ownedStart, 0)
        XCTAssertEqual(chunks.last?.ownedEnd, 10800)
        XCTAssertTrue(chunks.allSatisfy { $0.duration <= 56.5 })
        for index in 1..<chunks.count {
            XCTAssertEqual(chunks[index-1].ownedEnd, chunks[index].ownedStart)
            XCTAssertLessThan(chunks[index].sourceStart, chunks[index].ownedStart)
        }
    }

    func testOverlapDoesNotDuplicateWordsAtChunkBoundary() {
        let chunks = SpeechAnalysisChunk.plan(duration: 100)
        let first = chunks[0].project([.init(startSeconds: 54.8, durationSeconds: 0.6, text: "Grenze.", confidence: 1)])
        let second = chunks[1].project([.init(startSeconds: 0.55, durationSeconds: 0.6, text: "Grenze.", confidence: 1)])
        XCTAssertTrue(first.isEmpty)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].startSeconds, 54.8, accuracy: 0.001)
        XCTAssertEqual(second[0].text, "Grenze.")
    }

    func testInvalidSpeechDurationsDoNotCreateWork() {
        XCTAssertTrue(SpeechAnalysisChunk.plan(duration: .infinity).isEmpty)
        XCTAssertTrue(SpeechAnalysisChunk.plan(duration: -1).isEmpty)
        XCTAssertTrue(SpeechAnalysisChunk.plan(duration: 0).isEmpty)
    }
}
