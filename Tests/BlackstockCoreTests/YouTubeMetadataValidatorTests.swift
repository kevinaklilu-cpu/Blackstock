import XCTest
@testable import BlackstockCore

final class YouTubeMetadataValidatorTests: XCTestCase {
    func testValidMetadataPasses() throws {
        let metadata = YouTubeUploadMetadata(
            title: "Titel",
            description: "Beschreibung",
            defaultLanguage: "de",
            defaultAudioLanguage: "de-DE",
            localizations: [
                "en": .init(
                    title: "Title",
                    description: "Description"
                )
            ],
            selfDeclaredMadeForKids: false
        )

        XCTAssertNoThrow(
            try YouTubeMetadataValidator().validate(metadata)
        )
    }

    func testLocalizationRequiresDefaultLanguage() {
        let metadata = YouTubeUploadMetadata(
            title: "Titel",
            description: "",
            localizations: [
                "en": .init(
                    title: "Title",
                    description: ""
                )
            ],
            selfDeclaredMadeForKids: false
        )

        XCTAssertThrowsError(
            try YouTubeMetadataValidator().validate(metadata)
        ) {
            XCTAssertEqual(
                $0 as? YouTubeMetadataValidationError,
                .defaultLanguageRequiredForLocalizations
            )
        }
    }

    func testTitleLimitIsEnforced() {
        let metadata = YouTubeUploadMetadata(
            title: String(repeating: "a", count: 101),
            description: "",
            selfDeclaredMadeForKids: false
        )

        XCTAssertThrowsError(
            try YouTubeMetadataValidator().validate(metadata)
        ) {
            XCTAssertEqual(
                $0 as? YouTubeMetadataValidationError,
                .titleTooLong
            )
        }
    }

    func testDescriptionByteLimitIsEnforced() {
        let metadata = YouTubeUploadMetadata(
            title: "Titel",
            description: String(repeating: "ä", count: 2_501),
            selfDeclaredMadeForKids: false
        )

        XCTAssertThrowsError(
            try YouTubeMetadataValidator().validate(metadata)
        ) {
            XCTAssertEqual(
                $0 as? YouTubeMetadataValidationError,
                .descriptionTooLarge
            )
        }
    }
}
