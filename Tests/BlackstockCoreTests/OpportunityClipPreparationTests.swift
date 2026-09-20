import XCTest
@testable import BlackstockCore

final class OpportunityClipPreparationTests: XCTestCase {
    private func youtubeSource() -> MediaSourceReference {
        MediaSourceReference(
            provider: .youtube,
            pageURL: URL(string: "https://www.youtube.com/watch?v=abc123")!,
            externalID: "abc123",
            discoveredAt: Date(timeIntervalSince1970: 1)
        )
    }

    func testRequiresProductionMediaWhenYouTubeIngestIsNotApproved() {
        let source = youtubeSource()
        let resolution = MediaSourceResolver().resolve(
            source,
            approvedProvider: nil
        )

        let snapshot = OpportunityClipPreparationPlanner().snapshot(
            source: source,
            resolution: resolution,
            hasBoundAuthorizedMedia: false,
            isGeneratingClips: false,
            clipCount: 0,
            observedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(snapshot.status, .productionMediaRequired)
        XCTAssertEqual(snapshot.clipCount, 0)
    }

    func testBoundProductionMediaBecomesLocallyProcessable() {
        let source = youtubeSource()
        let resolution = MediaSourceResolver().resolve(
            source,
            approvedProvider: nil
        )

        let snapshot = OpportunityClipPreparationPlanner().snapshot(
            source: source,
            resolution: resolution,
            hasBoundAuthorizedMedia: true,
            isGeneratingClips: false,
            clipCount: 0,
            observedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(snapshot.status, .localProcessingReady)
    }

    func testGeneratingStateWinsWhileLocalClipJobRuns() {
        let source = youtubeSource()
        let resolution = MediaSourceResolver().resolve(
            source,
            approvedProvider: nil
        )

        let snapshot = OpportunityClipPreparationPlanner().snapshot(
            source: source,
            resolution: resolution,
            hasBoundAuthorizedMedia: true,
            isGeneratingClips: true,
            clipCount: 0,
            observedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(snapshot.status, .generatingClips)
    }

    func testAvailableCandidatesExposeRealCount() {
        let source = youtubeSource()
        let resolution = MediaSourceResolver().resolve(
            source,
            approvedProvider: nil
        )

        let snapshot = OpportunityClipPreparationPlanner().snapshot(
            source: source,
            resolution: resolution,
            hasBoundAuthorizedMedia: true,
            isGeneratingClips: false,
            clipCount: 4,
            observedAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual(snapshot.status, .clipsAvailable)
        XCTAssertEqual(snapshot.clipCount, 4)
    }
}
