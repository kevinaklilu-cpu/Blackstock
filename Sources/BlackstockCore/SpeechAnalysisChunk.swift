import Foundation

public struct SpeechAnalysisChunk: Sendable, Equatable {
    public let sourceStart: Double
    public let duration: Double
    public let ownedStart: Double
    public let ownedEnd: Double

    public static func plan(duration: Double, chunkLength: Double = 55, overlap: Double = 0.75) -> [Self] {
        guard duration.isFinite, duration > 0, chunkLength.isFinite, chunkLength >= 1,
              overlap.isFinite, overlap >= 0 else { return [] }
        var chunks: [Self] = []
        var cursor = 0.0
        while cursor < duration {
            let end = min(cursor + chunkLength, duration)
            let start = max(cursor - overlap, 0)
            chunks.append(.init(sourceStart: start, duration: min(end + overlap, duration) - start,
                                ownedStart: cursor, ownedEnd: end))
            cursor = end
        }
        return chunks
    }

    public func project(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.compactMap { segment in
            let start = sourceStart + segment.startSeconds
            let midpoint = start + segment.durationSeconds / 2
            guard midpoint >= ownedStart, midpoint < ownedEnd, segment.durationSeconds > 0 else { return nil }
            return .init(id: segment.id, startSeconds: start, durationSeconds: segment.durationSeconds,
                         text: segment.text, confidence: segment.confidence)
        }
    }
}
