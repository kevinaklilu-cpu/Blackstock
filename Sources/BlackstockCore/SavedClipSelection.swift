import Foundation

public struct SavedClipSelection:
    Codable,
    Sendable,
    Equatable,
    Identifiable {
    public let id: UUID
    public let sourceRange: EditTimeRange
    public let transcriptPreview: String
    public let wordCount: Int
    public let transcript: LocalTranscript?
    public let renderArtifact: RenderArtifact?
    public let savedAt: Date

    public init(
        id: UUID = UUID(),
        sourceRange: EditTimeRange,
        transcriptPreview: String,
        wordCount: Int,
        transcript: LocalTranscript? = nil,
        renderArtifact: RenderArtifact? = nil,
        savedAt: Date
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.transcriptPreview = transcriptPreview
        self.wordCount = max(wordCount, 0)
        self.transcript = transcript
        self.renderArtifact = renderArtifact
        self.savedAt = savedAt
    }

    public func withRenderArtifact(
        _ artifact: RenderArtifact?
    ) -> SavedClipSelection {
        SavedClipSelection(
            id: id,
            sourceRange: sourceRange,
            transcriptPreview: transcriptPreview,
            wordCount: wordCount,
            transcript: transcript,
            renderArtifact: artifact,
            savedAt: savedAt
        )
    }

    public init(
        candidate: LocalClipCandidate,
        transcript: LocalTranscript? = nil,
        savedAt: Date = Date()
    ) {
        self.init(
            sourceRange: candidate.sourceRange,
            transcriptPreview:
                candidate.transcriptPreview,
            wordCount: candidate.wordCount,
            transcript: transcript,
            renderArtifact: nil,
            savedAt: savedAt
        )
    }
}
