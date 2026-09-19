import XCTest
@testable import BlackstockCore

final class PackagingVariantsTests: XCTestCase {
    func testMaximumThreeVariants() throws {
        var set = try PackagingVariantSet()
        _ = try set.add(title: "A", at: Date())
        _ = try set.add(title: "B", at: Date())
        _ = try set.add(title: "C", at: Date())

        XCTAssertThrowsError(
            try set.add(title: "D", at: Date())
        ) {
            XCTAssertEqual(
                $0 as? PackagingVariantSetError,
                .maximumThreeVariants
            )
        }
    }

    func testEmptyVariantTitleIsRejected() throws {
        var set = try PackagingVariantSet()

        XCTAssertThrowsError(
            try set.add(title: "   ", at: Date())
        ) {
            XCTAssertEqual(
                $0 as? PackagingVariantSetError,
                .emptyTitle
            )
        }
    }

    func testWinnerCannotBePresentedWithoutYouTubeEvidence() throws {
        var set = try PackagingVariantSet()
        let a = try set.add(title: "A", at: Date())
        let b = try set.add(title: "B", at: Date())

        let pending = PackagingExperimentRecord(
            projectID: UUID(),
            variantIDs: [a.id, b.id],
            youtubeWinningVariantID: a.id,
            createdAt: Date()
        )

        XCTAssertFalse(pending.mayPresentYouTubeWinner)
    }

    func testYouTubeWinnerNeedsMatchingVariantAndReference() throws {
        var set = try PackagingVariantSet()
        let a = try set.add(title: "A", at: Date())
        let b = try set.add(title: "B", at: Date())

        let observed = PackagingExperimentRecord(
            projectID: UUID(),
            variantIDs: [a.id, b.id],
            interpretation: .observedOnly,
            youtubeExperimentReference: "youtube-studio-test-1",
            youtubeWinningVariantID: b.id,
            createdAt: Date()
        )

        XCTAssertTrue(observed.mayPresentYouTubeWinner)
    }
}
