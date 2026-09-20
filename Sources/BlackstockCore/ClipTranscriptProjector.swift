import Foundation

public struct ClipTranscriptProjector: Sendable {
    public init() {}

    public func project(
        source: LocalTranscript,
        candidate: LocalClipCandidate
    ) -> LocalTranscript? {
        let ids = Set(candidate.segmentIDs)
        let clipStart =
            candidate.sourceRange.startSeconds
        let clipEnd =
            candidate.sourceRange.endSeconds

        let segments = source.segments
            .filter {
                ids.contains($0.id)
            }
            .compactMap {
                segment -> TranscriptSegment? in
                let sourceStart =
                    segment.startSeconds
                let sourceEnd =
                    sourceStart
                    + max(
                        segment.durationSeconds,
                        0
                    )
                let overlapStart = max(
                    sourceStart,
                    clipStart
                )
                let overlapEnd = min(
                    sourceEnd,
                    clipEnd
                )
                guard overlapEnd
                    - overlapStart > 0.001 else {
                    return nil
                }

                return TranscriptSegment(
                    id: segment.id,
                    startSeconds: max(
                        overlapStart
                        - clipStart,
                        0
                    ),
                    durationSeconds:
                        overlapEnd
                        - overlapStart,
                    text: segment.text,
                    confidence:
                        segment.confidence
                )
            }
            .sorted {
                $0.startSeconds
                    < $1.startSeconds
            }

        guard !segments.isEmpty else {
            return nil
        }

        return LocalTranscript(
            localeIdentifier:
                source.localeIdentifier,
            text: segments
                .map(\.text)
                .joined(separator: " "),
            segments: segments,
            onDevice: source.onDevice,
            createdAt: Date()
        )
    }
}
