import XCTest
@testable import BlackstockCore

final class ReframeGeometryTests: XCTestCase {
    func testLandscapeToPortraitCenterCrop() throws {
        let plan = try XCTUnwrap(
            ReframeCropPlan.make(
                sourceWidth: 1920,
                sourceHeight: 1080,
                spec: .init(
                    aspectRatio: .portrait9x16,
                    focalX: 0.5,
                    focalY: 0.5
                )
            )
        )

        XCTAssertEqual(plan.cropHeight, 1080, accuracy: 0.001)
        XCTAssertEqual(plan.cropWidth, 607.5, accuracy: 0.001)
        XCTAssertEqual(plan.cropX, 656.25, accuracy: 0.001)
        XCTAssertEqual(plan.cropY, 0, accuracy: 0.001)
    }

    func testFocalPointMovesHorizontalCropWithoutLeavingBounds() throws {
        let left = try XCTUnwrap(
            ReframeCropPlan.make(
                sourceWidth: 1920,
                sourceHeight: 1080,
                spec: .init(
                    aspectRatio: .square1x1,
                    focalX: 0,
                    focalY: 0.5
                )
            )
        )
        let right = try XCTUnwrap(
            ReframeCropPlan.make(
                sourceWidth: 1920,
                sourceHeight: 1080,
                spec: .init(
                    aspectRatio: .square1x1,
                    focalX: 1,
                    focalY: 0.5
                )
            )
        )

        XCTAssertEqual(left.cropX, 0, accuracy: 0.001)
        XCTAssertEqual(right.cropX + right.cropWidth, 1920, accuracy: 0.001)
    }

    func testPortraitToLandscapeUsesVerticalFocalPoint() throws {
        let plan = try XCTUnwrap(
            ReframeCropPlan.make(
                sourceWidth: 1080,
                sourceHeight: 1920,
                spec: .init(
                    aspectRatio: .landscape16x9,
                    focalX: 0.5,
                    focalY: 1
                )
            )
        )

        XCTAssertEqual(plan.cropWidth, 1080, accuracy: 0.001)
        XCTAssertEqual(plan.cropHeight, 607.5, accuracy: 0.001)
        XCTAssertEqual(plan.cropY + plan.cropHeight, 1920, accuracy: 0.001)
    }

    func testReframeSpecClampsManualFocus() {
        let spec = ReframeSpec(
            aspectRatio: .portrait9x16,
            focalX: -5,
            focalY: 4
        )

        XCTAssertEqual(spec.focalX, 0)
        XCTAssertEqual(spec.focalY, 1)
    }

    func testInvalidSourceSizeProducesNoPlan() {
        XCTAssertNil(
            ReframeCropPlan.make(
                sourceWidth: 0,
                sourceHeight: 1080,
                spec: .init(aspectRatio: .landscape16x9)
            )
        )
    }
}
