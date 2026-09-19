import XCTest
import CoreGraphics
@testable import BlackstockCore

#if os(macOS)
final class ReframeTransformPlanTests: XCTestCase {
    func testLandscapeCenterCropScalesToPortraitRenderSize() throws {
        let plan = try XCTUnwrap(
            ReframeTransformPlan.make(
                naturalSize: CGSize(width: 1920, height: 1080),
                preferredTransform: .identity,
                spec: .init(aspectRatio: .portrait9x16),
                renderSize: CGSize(width: 1080, height: 1920)
            )
        )

        XCTAssertEqual(plan.crop.cropWidth, 607.5, accuracy: 0.001)
        XCTAssertEqual(plan.crop.cropHeight, 1080, accuracy: 0.001)
        XCTAssertEqual(plan.renderWidth, 1080, accuracy: 0.001)
        XCTAssertEqual(plan.renderHeight, 1920, accuracy: 0.001)
    }

    func testPortraitRotationNormalizesNegativeBounds() throws {
        let rotation = CGAffineTransform(
            a: 0,
            b: 1,
            c: -1,
            d: 0,
            tx: 1080,
            ty: 0
        )

        let plan = try XCTUnwrap(
            ReframeTransformPlan.make(
                naturalSize: CGSize(width: 1920, height: 1080),
                preferredTransform: rotation,
                spec: .init(aspectRatio: .portrait9x16),
                renderSize: CGSize(width: 1080, height: 1920)
            )
        )

        XCTAssertEqual(plan.crop.sourceWidth, 1080, accuracy: 0.001)
        XCTAssertEqual(plan.crop.sourceHeight, 1920, accuracy: 0.001)
        XCTAssertEqual(plan.crop.cropWidth, 1080, accuracy: 0.001)
        XCTAssertEqual(plan.crop.cropHeight, 1920, accuracy: 0.001)
    }

    func testPresetRenderSizesMatchRequestedAspect() {
        XCTAssertEqual(
            LocalRenderPreset.hd1080.renderSize(for: .portrait9x16),
            CGSize(width: 1080, height: 1920)
        )
        XCTAssertEqual(
            LocalRenderPreset.uhd4K.renderSize(for: .landscape16x9),
            CGSize(width: 3840, height: 2160)
        )
    }
}
#endif
