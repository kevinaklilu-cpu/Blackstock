import XCTest
@testable import BlackstockCore

final class LocalHighlightCandidateRankerTests: XCTestCase {
    func testPrefersDenseConfidentClipNearTargetDuration() {
        let weak = LocalClipCandidate(
            sourceRange: .init(
                startSeconds: 180,
                durationSeconds: 70
            ),
            transcriptPreview: "Langer Abschnitt",
            wordCount: 55,
            averageConfidence: 0.55,
            segmentIDs: []
        )
        let strong = LocalClipCandidate(
            sourceRange: .init(
                startSeconds: 20,
                durationSeconds: 36
            ),
            transcriptPreview: "Kompakter klarer Abschnitt",
            wordCount: 82,
            averageConfidence: 0.94,
            segmentIDs: []
        )

        let ranked = LocalHighlightCandidateRanker()
            .rank([weak, strong])

        XCTAssertEqual(ranked.first?.id, strong.id)
    }

    func testRankingIsStableWhenScoresTie() {
        let later = LocalClipCandidate(
            sourceRange: .init(
                startSeconds: 50,
                durationSeconds: 35
            ),
            transcriptPreview: "B",
            wordCount: 70,
            averageConfidence: 0.9,
            segmentIDs: []
        )
        let earlier = LocalClipCandidate(
            sourceRange: .init(
                startSeconds: 10,
                durationSeconds: 35
            ),
            transcriptPreview: "A",
            wordCount: 70,
            averageConfidence: 0.9,
            segmentIDs: []
        )

        let ranked = LocalHighlightCandidateRanker()
            .rank([later, earlier])

        XCTAssertEqual(ranked.map(\.id), [earlier.id, later.id])
    }
}
