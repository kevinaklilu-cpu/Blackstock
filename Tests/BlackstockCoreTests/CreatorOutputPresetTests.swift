import XCTest
@testable import BlackstockCore

final class CreatorOutputPresetTests: XCTestCase {
    func testLandscapePresetMapsToLandscapeAndClearCaptions() {
        XCTAssertEqual(
            CreatorOutputPreset.youtubeLandscape.aspectRatio,
            .landscape16x9
        )
        XCTAssertEqual(
            CreatorOutputPreset.youtubeLandscape.captionStyle,
            .clear
        )
        XCTAssertFalse(
            CreatorOutputPreset.youtubeLandscape
                .prefersVisibleCaptions
        )
    }

    func testShortPresetMapsToPortraitAndStrongCaptions() {
        XCTAssertEqual(
            CreatorOutputPreset.shortVertical.aspectRatio,
            .portrait9x16
        )
        XCTAssertEqual(
            CreatorOutputPreset.shortVertical.captionStyle,
            .strong
        )
        XCTAssertTrue(
            CreatorOutputPreset.shortVertical
                .prefersVisibleCaptions
        )
    }

    func testSquarePresetMapsToSquareAndVisibleCaptions() {
        XCTAssertEqual(
            CreatorOutputPreset.squareSocial.aspectRatio,
            .square1x1
        )
        XCTAssertEqual(
            CreatorOutputPreset.squareSocial.captionStyle,
            .clear
        )
        XCTAssertTrue(
            CreatorOutputPreset.squareSocial
                .prefersVisibleCaptions
        )
    }

    func testAllPresetsHaveGermanProductCopy() {
        for preset in CreatorOutputPreset.allCases {
            XCTAssertFalse(
                preset.germanTitle
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
            )
            XCTAssertFalse(
                preset.germanExplanation
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
            )
        }
    }
}
