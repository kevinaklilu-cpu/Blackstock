import Foundation

public struct PublishThumbnail: Codable, Sendable, Equatable {
    public let fileURL: URL
    public let mimeType: String

    public init(fileURL: URL, mimeType: String) {
        self.fileURL = fileURL
        self.mimeType = mimeType
    }
}

public struct PublishCaptionTrack: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let language: String
    public let name: String
    public let fileURL: URL
    public let mimeType: String
    public let isDraft: Bool

    public init(
        id: UUID = UUID(),
        language: String,
        name: String,
        fileURL: URL,
        mimeType: String,
        isDraft: Bool = false
    ) {
        self.id = id
        self.language = language
        self.name = name
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.isDraft = isDraft
    }
}

public struct PublishPackage: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let targetChannelID: String
    public let renderArtifactID: UUID
    public let metadata: YouTubeUploadMetadata
    public let thumbnail: PublishThumbnail?
    public let captions: [PublishCaptionTrack]

    public init(
        projectID: UUID,
        targetChannelID: String,
        renderArtifactID: UUID,
        metadata: YouTubeUploadMetadata,
        thumbnail: PublishThumbnail?,
        captions: [PublishCaptionTrack]
    ) {
        self.projectID = projectID
        self.targetChannelID = targetChannelID
        self.renderArtifactID = renderArtifactID
        self.metadata = metadata
        self.thumbnail = thumbnail
        self.captions = captions
    }
}

public enum PublishPackageValidationError: Error, Sendable, Equatable {
    case projectMismatch
    case channelMismatch
    case renderMismatch
    case renderNotValidated
    case qualityReviewMissing
    case qualityReviewFailed
    case rightsNotValidated
    case titleMissing
    case publicPublishingNotAllowed
    case userConfirmationRequired
}

public struct PublishReviewContext: Sendable, Equatable {
    public let project: BlackstockProject
    public let artifact: RenderArtifact
    public let package: PublishPackage
    public let qualityReview: CreatorQualityReview?
    public let rightsValidated: Bool
    public let publicPublishingAllowed: Bool
    public let userConfirmed: Bool

    public init(
        project: BlackstockProject,
        artifact: RenderArtifact,
        package: PublishPackage,
        qualityReview: CreatorQualityReview?,
        rightsValidated: Bool,
        publicPublishingAllowed: Bool,
        userConfirmed: Bool
    ) {
        self.project = project
        self.artifact = artifact
        self.package = package
        self.qualityReview = qualityReview
        self.rightsValidated = rightsValidated
        self.publicPublishingAllowed = publicPublishingAllowed
        self.userConfirmed = userConfirmed
    }

    public func validate() throws {
        guard package.projectID == project.id else {
            throw PublishPackageValidationError.projectMismatch
        }
        guard package.targetChannelID == project.targetChannelID else {
            throw PublishPackageValidationError.channelMismatch
        }
        guard package.renderArtifactID == artifact.id,
              artifact.projectID == project.id else {
            throw PublishPackageValidationError.renderMismatch
        }
        guard artifact.validated else {
            throw PublishPackageValidationError.renderNotValidated
        }
        guard let qualityReview else {
            throw PublishPackageValidationError.qualityReviewMissing
        }
        guard qualityReview.projectID == project.id,
              qualityReview.passesReleaseGate else {
            throw PublishPackageValidationError.qualityReviewFailed
        }
        guard rightsValidated else {
            throw PublishPackageValidationError.rightsNotValidated
        }
        guard !package.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PublishPackageValidationError.titleMissing
        }
        if package.metadata.privacyStatus != .privateVideo && !publicPublishingAllowed {
            throw PublishPackageValidationError.publicPublishingNotAllowed
        }
        guard ActionAuthorization(
            riskClass: .remoteHighImpact,
            deterministicChecksPassed: true,
            userConfirmed: userConfirmed
        ).mayExecute else {
            throw PublishPackageValidationError.userConfirmationRequired
        }
    }
}
