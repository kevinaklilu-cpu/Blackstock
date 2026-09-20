import Foundation

public struct SupplementalCaptureAsset:
    Codable,
    Sendable,
    Equatable,
    Identifiable {

    public let id: UUID
    public let projectID: UUID
    public let kind: CaptureKind
    public let fileURL: URL
    public let mimeType: String
    public let rightsBasis: String
    public let rightsEvidence: String
    public let rightsConfirmed: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        kind: CaptureKind,
        fileURL: URL,
        mimeType: String,
        rightsBasis: String,
        rightsEvidence: String,
        rightsConfirmed: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.rightsBasis = rightsBasis
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightsEvidence = rightsEvidence
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.rightsConfirmed = rightsConfirmed
        self.createdAt = createdAt
    }

    public var mayBeUsedInProduction: Bool {
        rightsConfirmed
            && !rightsBasis.isEmpty
            && !rightsEvidence.isEmpty
    }
}


public struct SupplementalAudioMixSetting:
    Codable,
    Sendable,
    Equatable,
    Identifiable {

    public let captureID: UUID
    public var enabled: Bool
    public var volume: Double

    public var id: UUID { captureID }

    public init(
        captureID: UUID,
        enabled: Bool = false,
        volume: Double = 0.75
    ) {
        self.captureID = captureID
        self.enabled = enabled
        self.volume = min(max(volume, 0), 1)
    }
}

public struct SupplementalAudioMixInput:
    Sendable,
    Equatable,
    Identifiable {

    public let captureID: UUID
    public let fileURL: URL
    public let volume: Double

    public var id: UUID { captureID }

    public init(
        captureID: UUID,
        fileURL: URL,
        volume: Double
    ) {
        self.captureID = captureID
        self.fileURL = fileURL
        self.volume = min(max(volume, 0), 1)
    }
}
