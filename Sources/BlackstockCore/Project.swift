import Foundation

public struct BlackstockProject: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public let targetChannelID: String
    public private(set) var stage: BlackstockStage
    public let strategyVersion: Int
    public let createdAt: Date
    public private(set) var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        targetChannelID: String,
        stage: BlackstockStage = .production,
        strategyVersion: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.targetChannelID = targetChannelID
        self.stage = stage
        self.strategyVersion = strategyVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func advance(to destination: BlackstockStage, at date: Date) -> Bool {
        guard stage.canTransition(to: destination) else { return false }
        stage = destination
        updatedAt = date
        return true
    }
}

public enum RenderRequestedQuality: String, Codable, Sendable, Equatable {
    case upTo1080p = "UP_TO_1080P"
    case upTo4K = "UP_TO_4K"
}

public struct RenderArtifact: Codable, Sendable, Equatable, Identifiable {
    public static let currentValidationVersion = "render-technical-v1"

    public let id: UUID
    public let projectID: UUID
    public let fileURL: URL
    public let sha256: String
    public let mimeType: String
    public let validated: Bool
    public let validationVersion: String?
    public let requestedQuality: RenderRequestedQuality?
    public let technicalSnapshot: RenderTechnicalSnapshot?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        fileURL: URL,
        sha256: String,
        mimeType: String,
        validated: Bool,
        validationVersion: String? = RenderArtifact.currentValidationVersion,
        requestedQuality: RenderRequestedQuality? = nil,
        technicalSnapshot: RenderTechnicalSnapshot? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.fileURL = fileURL
        self.sha256 = sha256
        self.mimeType = mimeType
        self.validated = validated
        self.validationVersion = validationVersion
        self.requestedQuality = requestedQuality
        self.technicalSnapshot = technicalSnapshot
        self.createdAt = createdAt
    }

    public var hasCurrentTechnicalValidation: Bool {
        validated
            && validationVersion == Self.currentValidationVersion
    }
}
