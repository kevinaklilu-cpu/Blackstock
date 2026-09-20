import Foundation

public enum CaptionSegmentEditError:
    Error,
    Sendable,
    Equatable,
    LocalizedError {
    case segmentNotFound
    case emptyText
    case invalidTimeRange
    case outsideOutputDuration
    case overlappingSegments

    public var errorDescription: String? {
        switch self {
        case .segmentNotFound:
            return "Das Untertitelsegment wurde nicht gefunden."
        case .emptyText:
            return "Der Untertiteltext darf nicht leer sein."
        case .invalidTimeRange:
            return "Start und Dauer müssen gültige, endliche Werte sein; die Dauer muss mindestens 0,05 Sekunden betragen."
        case .outsideOutputDuration:
            return "Das Untertitelsegment liegt außerhalb der aktuellen Schnittdauer."
        case .overlappingSegments:
            return "Untertitelsegmente dürfen sich nicht zeitlich überlappen."
        }
    }
}

public struct LocalTranscriptEditor: Sendable {
    public init() {}

    public func updatingSegment(
        in transcript: LocalTranscript,
        id: UUID,
        text: String,
        startSeconds: Double,
        durationSeconds: Double,
        outputDurationSeconds: Double,
        editedAt: Date = Date()
    ) throws -> LocalTranscript {
        guard let index = transcript.segments.firstIndex(
            where: { $0.id == id }
        ) else {
            throw CaptionSegmentEditError.segmentNotFound
        }

        let cleanText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanText.isEmpty else {
            throw CaptionSegmentEditError.emptyText
        }
        guard startSeconds.isFinite,
              durationSeconds.isFinite,
              outputDurationSeconds.isFinite,
              startSeconds >= 0,
              durationSeconds >= 0.05,
              outputDurationSeconds > 0 else {
            throw CaptionSegmentEditError.invalidTimeRange
        }

        let endSeconds = startSeconds + durationSeconds
        guard endSeconds <= outputDurationSeconds + 0.001 else {
            throw CaptionSegmentEditError.outsideOutputDuration
        }

        let original = transcript.segments[index]
        var segments = transcript.segments
        segments[index] = TranscriptSegment(
            id: original.id,
            startSeconds: startSeconds,
            durationSeconds: durationSeconds,
            text: cleanText,
            confidence: original.confidence,
            editedByUser: true,
            editedAt: editedAt
        )
        segments.sort {
            if abs($0.startSeconds - $1.startSeconds) < 0.000_001 {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.startSeconds < $1.startSeconds
        }

        for pair in zip(segments, segments.dropFirst()) {
            let previousEnd =
                pair.0.startSeconds + pair.0.durationSeconds
            if previousEnd > pair.1.startSeconds + 0.001 {
                throw CaptionSegmentEditError.overlappingSegments
            }
        }

        return LocalTranscript(
            localeIdentifier: transcript.localeIdentifier,
            text: segments
                .map(\.text)
                .joined(separator: " "),
            segments: segments,
            onDevice: transcript.onDevice,
            createdAt: transcript.createdAt
        )
    }
}
