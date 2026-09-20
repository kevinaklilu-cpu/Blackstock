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
    public let savedAt: Date

    public init(
        id: UUID = UUID(),
        sourceRange: EditTimeRange,
        transcriptPreview: String,
        wordCount: Int,
        savedAt: Date
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.transcriptPreview = transcriptPreview
        self.wordCount = max(wordCount, 0)
        self.savedAt = savedAt
    }

    public init(
        candidate: LocalClipCandidate,
        savedAt: Date = Date()
    ) {
        self.init(
            sourceRange: candidate.sourceRange,
            transcriptPreview:
                candidate.transcriptPreview,
            wordCount: candidate.wordCount,
            savedAt: savedAt
        )
    }
}
