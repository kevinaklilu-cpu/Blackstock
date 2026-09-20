#if os(macOS)
import XCTest
@testable import BlackstockCore

final class LocalThumbnailFrameGeneratorTests: XCTestCase {
    func testLandscapeFrameCenterCropsToSixteenByNine() throws {
        let rect = try XCTUnwrap(
            LocalThumbnailFrameGenerator.centerCropRect(
                sourceWidth: 1_920,
                sourceHeight: 1_080,
                targetAspectRatio: 16.0 / 9.0
            )
        )

        XCTAssertEqual(rect.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1_920, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1_080, accuracy: 0.001)
    }

    func testPortraitFrameCenterCropsToSixteenByNine() throws {
        let rect = try XCTUnwrap(
            LocalThumbnailFrameGenerator.centerCropRect(
                sourceWidth: 1_080,
                sourceHeight: 1_920,
                targetAspectRatio: 16.0 / 9.0
            )
        )

        XCTAssertEqual(rect.width / rect.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertEqual(rect.midX, 540, accuracy: 1)
        XCTAssertEqual(rect.midY, 960, accuracy: 1)
    }

    func testInvalidGeometryIsRejected() {
        XCTAssertNil(
            LocalThumbnailFrameGenerator.centerCropRect(
                sourceWidth: 0,
                sourceHeight: 1_080,
                targetAspectRatio: 16.0 / 9.0
            )
        )
    }
}
#endif
