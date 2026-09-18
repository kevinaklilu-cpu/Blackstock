import Foundation

public struct ClipJobCreateRequest: Codable, Sendable, Equatable {
    public let sourceURL: URL
    public let title: String
    public let sourceLanguage: String?
    public let prompt: String?
    public let rightsEvidence: String
    public let rightsConfirmed: Bool

    public init(
        sourceURL: URL,
        title: String,
        sourceLanguage: String?,
        prompt: String?,
        rightsEvidence: String,
        rightsConfirmed: Bool
    ) {
        self.sourceURL = sourceURL
        self.title = title
        self.sourceLanguage = sourceLanguage
        self.prompt = prompt
        self.rightsEvidence = rightsEvidence
        self.rightsConfirmed = rightsConfirmed
    }
}

public enum ClipJobState: String, Codable, Sendable {
    case submitted = "SUBMITTED"
    case resolvingSource = "RESOLVING_SOURCE"
    case processing = "PROCESSING"
    case clipsReady = "CLIPS_READY"
    case failed = "FAILED"
}

public struct ClipArtifact: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let providerID: String
    public let providerArtifactID: String?
    public let title: String
    public let text: String?
    public let durationMs: Int?
    public let previewURL: URL?
    public let exportURL: URL?
    public let sourceTimeRanges: [[Int]]
    public let createdAt: Date?

    public init(
        id: String,
        providerID: String,
        providerArtifactID: String?,
        title: String,
        text: String?,
        durationMs: Int?,
        previewURL: URL?,
        exportURL: URL?,
        sourceTimeRanges: [[Int]],
        createdAt: Date?
    ) {
        self.id = id
        self.providerID = providerID
        self.providerArtifactID = providerArtifactID
        self.title = title
        self.text = text
        self.durationMs = durationMs
        self.previewURL = previewURL
        self.exportURL = exportURL
        self.sourceTimeRanges = sourceTimeRanges
        self.createdAt = createdAt
    }
}

public struct ClipJobStatus: Codable, Sendable, Equatable {
    public let jobID: String
    public let providerID: String?
    public let providerProjectID: String?
    public let state: ClipJobState
    public let providerStage: String?
    public let message: String?
    public let clips: [ClipArtifact]

    public init(
        jobID: String,
        providerID: String?,
        providerProjectID: String?,
        state: ClipJobState,
        providerStage: String?,
        message: String?,
        clips: [ClipArtifact] = []
    ) {
        self.jobID = jobID
        self.providerID = providerID
        self.providerProjectID = providerProjectID
        self.state = state
        self.providerStage = providerStage
        self.message = message
        self.clips = clips
    }
}
