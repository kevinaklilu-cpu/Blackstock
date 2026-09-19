import XCTest
@testable import BlackstockCore

#if os(macOS)
final class ThumbnailTechnicalInspectorTests: XCTestCase {
    func testValidSixteenByNineJPEGHasNoTechnicalFindings() {
        let snapshot = ThumbnailTechnicalSnapshot(
            width: 3840,
            height: 2160,
            fileSizeBytes: 4 * 1_024 * 1_024,
            mimeType: "image/jpeg",
            inspectedAt: Date()
        )

        let assessment = ThumbnailTechnicalAssessment.evaluate(snapshot)

        XCTAssertTrue(assessment.uploadCompatible)
        XCTAssertTrue(assessment.uploadBlockers.isEmpty)
        XCTAssertTrue(assessment.bestPracticeFindings.isEmpty)
    }

    func testUnsupportedMimeTypeIsUploadBlocker() {
        let snapshot = ThumbnailTechnicalSnapshot(
            width: 1920,
            height: 1080,
            fileSizeBytes: 1_000,
            mimeType: "image/tiff",
            inspectedAt: Date()
        )

        XCTAssertEqual(
            ThumbnailTechnicalAssessment.evaluate(snapshot).uploadBlockers,
            [.unsupportedMimeType]
        )
    }

    func testOversizeFileIsUploadBlocker() {
        let snapshot = ThumbnailTechnicalSnapshot(
            width: 1920,
            height: 1080,
            fileSizeBytes: 51 * 1_024 * 1_024,
            mimeType: "image/png",
            inspectedAt: Date()
        )

        XCTAssertEqual(
            ThumbnailTechnicalAssessment.evaluate(snapshot).uploadBlockers,
            [.exceedsFiftyMB]
        )
    }

    func testSmallNonSixteenByNineImageProducesBestPracticeFindingsOnly() {
        let snapshot = ThumbnailTechnicalSnapshot(
            width: 500,
            height: 500,
            fileSizeBytes: 500_000,
            mimeType: "image/png",
            inspectedAt: Date()
        )

        let assessment = ThumbnailTechnicalAssessment.evaluate(snapshot)

        XCTAssertTrue(assessment.uploadCompatible)
        XCTAssertEqual(
            Set(assessment.bestPracticeFindings),
            Set([
                .belowRecommendedMinimumWidth,
                .notSixteenByNine
            ])
        )
    }
}
#endif
