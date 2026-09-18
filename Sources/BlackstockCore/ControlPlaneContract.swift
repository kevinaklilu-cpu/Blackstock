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
    case processing = "PROCESSING"
    case clipsReady = "CLIPS_READY"
    case failed = "FAILED"
}

public struct ClipJobStatus: Codable, Sendable, Equatable {
    public let jobID: String
    public let providerProjectID: String?
    public let state: ClipJobState
    public let providerStage: String?
    public let message: String?
    public let clips: [OpusClipExportableClip]

    public init(
        jobID: String,
        providerProjectID: String?,
        state: ClipJobState,
        providerStage: String?,
        message: String?,
        clips: [OpusClipExportableClip] = []
    ) {
        self.jobID = jobID
        self.providerProjectID = providerProjectID
        self.state = state
        self.providerStage = providerStage
        self.message = message
        self.clips = clips
    }
}
