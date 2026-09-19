import Foundation

public struct PackagingVariant: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var thumbnailURL: URL?
    public var note: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        thumbnailURL: URL? = nil,
        note: String = "",
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PackagingVariantSetError: Error, Sendable, Equatable {
    case maximumThreeVariants
    case variantNotFound
    case emptyTitle
}

public struct PackagingVariantSet: Codable, Sendable, Equatable {
    public private(set) var variants: [PackagingVariant]

    public init() {
        self.variants = []
    }

    public init(variants: [PackagingVariant]) throws {
        guard variants.count <= 3 else {
            throw PackagingVariantSetError.maximumThreeVariants
        }
        self.variants = variants
    }

    @discardableResult
    public mutating func add(
        title: String,
        thumbnailURL: URL? = nil,
        note: String = "",
        at date: Date
    ) throws -> PackagingVariant {
        guard variants.count < 3 else {
            throw PackagingVariantSetError.maximumThreeVariants
        }

        let cleanTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanTitle.isEmpty else {
            throw PackagingVariantSetError.emptyTitle
        }

        let variant = PackagingVariant(
            title: cleanTitle,
            thumbnailURL: thumbnailURL,
            note: note,
            createdAt: date,
            updatedAt: date
        )
        variants.append(variant)
        return variant
    }

    public mutating func update(
        id: UUID,
        title: String? = nil,
        thumbnailURL: URL?? = nil,
        note: String? = nil,
        at date: Date
    ) throws {
        guard let index = variants.firstIndex(
            where: { $0.id == id }
        ) else {
            throw PackagingVariantSetError.variantNotFound
        }

        if let title {
            let clean = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !clean.isEmpty else {
                throw PackagingVariantSetError.emptyTitle
            }
            variants[index].title = clean
        }

        if let thumbnailURL {
            variants[index].thumbnailURL = thumbnailURL
        }

        if let note {
            variants[index].note = note
        }

        variants[index].updatedAt = date
    }

    public mutating func remove(id: UUID) throws {
        guard let index = variants.firstIndex(
            where: { $0.id == id }
        ) else {
            throw PackagingVariantSetError.variantNotFound
        }
        variants.remove(at: index)
    }
}

public enum PackagingExperimentInterpretation: String, Codable, Sendable {
    case awaitingYouTubeData = "AWAITING_YOUTUBE_DATA"
    case observedOnly = "OBSERVED_ONLY"
}

public struct PackagingExperimentRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let variantIDs: [UUID]
    public let interpretation: PackagingExperimentInterpretation
    public let youtubeExperimentReference: String?
    public let youtubeWinningVariantID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        variantIDs: [UUID],
        interpretation: PackagingExperimentInterpretation = .awaitingYouTubeData,
        youtubeExperimentReference: String? = nil,
        youtubeWinningVariantID: UUID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.variantIDs = Array(variantIDs.prefix(3))
        self.interpretation = interpretation
        self.youtubeExperimentReference = youtubeExperimentReference
        self.youtubeWinningVariantID = youtubeWinningVariantID
        self.createdAt = createdAt
    }

    public var mayPresentYouTubeWinner: Bool {
        guard interpretation == .observedOnly,
              let youtubeExperimentReference,
              !youtubeExperimentReference.isEmpty,
              let youtubeWinningVariantID else {
            return false
        }
        return variantIDs.contains(youtubeWinningVariantID)
    }
}
