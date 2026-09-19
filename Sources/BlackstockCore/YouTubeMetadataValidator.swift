import Foundation

public enum YouTubeMetadataValidationError: Error, Sendable, Equatable {
    case emptyTitle
    case titleTooLong
    case descriptionTooLarge
    case defaultLanguageRequiredForLocalizations
    case emptyLocalizationLanguage
    case localizedTitleTooLong(language: String)
    case localizedDescriptionTooLarge(language: String)
}

public struct YouTubeMetadataValidator: Sendable {
    public init() {}

    public func validate(
        _ metadata: YouTubeUploadMetadata
    ) throws {
        let title = metadata.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty else {
            throw YouTubeMetadataValidationError.emptyTitle
        }
        guard title.count <= 100 else {
            throw YouTubeMetadataValidationError.titleTooLong
        }
        guard metadata.description.utf8.count <= 5_000 else {
            throw YouTubeMetadataValidationError.descriptionTooLarge
        }

        if !metadata.localizations.isEmpty {
            guard let defaultLanguage = metadata.defaultLanguage,
                  !defaultLanguage.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                throw YouTubeMetadataValidationError
                    .defaultLanguageRequiredForLocalizations
            }
        }

        for (language, localization) in metadata.localizations {
            let cleanLanguage = language.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !cleanLanguage.isEmpty else {
                throw YouTubeMetadataValidationError
                    .emptyLocalizationLanguage
            }
            guard localization.title.count <= 100 else {
                throw YouTubeMetadataValidationError
                    .localizedTitleTooLong(language: cleanLanguage)
            }
            guard localization.description.utf8.count <= 5_000 else {
                throw YouTubeMetadataValidationError
                    .localizedDescriptionTooLarge(language: cleanLanguage)
            }
        }
    }
}
