import Foundation

public struct LocalClipCandidate:
    Codable,
    Sendable,
    Equatable,
    Identifiable {
    public let id: UUID
    public let sourceRange: EditTimeRange
    public let transcriptPreview: String
    public let wordCount: Int
    public let averageConfidence: Float?
    public let segmentIDs: [UUID]

    public init(
        id: UUID = UUID(),
        sourceRange: EditTimeRange,
        transcriptPreview: String,
        wordCount: Int,
        averageConfidence: Float?,
        segmentIDs: [UUID]
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.transcriptPreview = transcriptPreview
        self.wordCount = max(wordCount, 0)
        self.averageConfidence = averageConfidence
        self.segmentIDs = segmentIDs
    }
}

public struct LocalClipCandidateGenerator: Sendable {
    public init() {}

    public func generate(
        transcript: LocalTranscript,
        sourceDurationSeconds: Double,
        minimumDurationSeconds: Double = 15,
        maximumDurationSeconds: Double = 75,
        pauseBoundarySeconds: Double = 2.5,
        maximumCandidates: Int = 8
    ) -> [LocalClipCandidate] {
        let minimumDuration = max(minimumDurationSeconds, 1)
        let maximumDuration = max(
            maximumDurationSeconds,
            minimumDuration
        )
        let pauseBoundary = max(pauseBoundarySeconds, 0.25)
        let sourceDuration = max(sourceDurationSeconds, 0)

        let segments = transcript.segments
            .filter {
                !$0.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                && $0.durationSeconds > 0
            }
            .sorted {
                if $0.startSeconds == $1.startSeconds {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.startSeconds < $1.startSeconds
            }

        guard !segments.isEmpty,
              sourceDuration > 0,
              maximumCandidates > 0 else {
            return []
        }

        var groups: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []

        for segment in segments {
            guard let previous = current.last else {
                current = [segment]
                continue
            }

            let previousEnd =
                previous.startSeconds
                + max(previous.durationSeconds, 0)
            let gap = max(
                segment.startSeconds - previousEnd,
                0
            )

            if gap >= pauseBoundary {
                groups.append(current)
                current = [segment]
            } else {
                current.append(segment)
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }

        var candidates: [LocalClipCandidate] = []

        for group in groups {
            var chunk: [TranscriptSegment] = []

            for segment in group {
                if chunk.isEmpty {
                    chunk = [segment]
                    continue
                }

                let proposedStart =
                    chunk.first?.startSeconds
                    ?? segment.startSeconds
                let proposedEnd =
                    segment.startSeconds
                    + max(segment.durationSeconds, 0)

                if proposedEnd - proposedStart
                    > maximumDuration {
                    appendCandidate(
                        from: chunk,
                        sourceDurationSeconds: sourceDuration,
                        minimumDurationSeconds: minimumDuration,
                        maximumDurationSeconds: maximumDuration,
                        to: &candidates
                    )
                    chunk = [segment]
                } else {
                    chunk.append(segment)
                }
            }

            appendCandidate(
                from: chunk,
                sourceDurationSeconds: sourceDuration,
                minimumDurationSeconds: minimumDuration,
                maximumDurationSeconds: maximumDuration,
                to: &candidates
            )

            if candidates.count >= maximumCandidates {
                break
            }
        }

        return Array(
            candidates.prefix(maximumCandidates)
        )
    }

    private func appendCandidate(
        from segments: [TranscriptSegment],
        sourceDurationSeconds: Double,
        minimumDurationSeconds: Double,
        maximumDurationSeconds: Double,
        to candidates: inout [LocalClipCandidate]
    ) {
        guard let first = segments.first,
              let last = segments.last else {
            return
        }

        let speechStart = max(
            first.startSeconds,
            0
        )
        let speechEnd = min(
            last.startSeconds
                + max(last.durationSeconds, 0),
            sourceDurationSeconds
        )
        let speechDuration = max(
            speechEnd - speechStart,
            0
        )
        guard speechDuration > 0 else {
            return
        }

        let maximumDuration = max(
            maximumDurationSeconds,
            minimumDurationSeconds
        )
        let boundedSpeechEnd = min(
            speechEnd,
            speechStart + maximumDuration
        )
        let boundedSpeechDuration = max(
            boundedSpeechEnd - speechStart,
            0
        )

        let availablePadding = max(
            maximumDuration
                - boundedSpeechDuration,
            0
        )
        let leadingPadding = min(
            0.35,
            speechStart,
            availablePadding / 2
        )
        let trailingPadding = min(
            0.35,
            max(
                sourceDurationSeconds
                    - boundedSpeechEnd,
                0
            ),
            availablePadding
                - leadingPadding
        )
        let rawStart =
            speechStart - leadingPadding
        let rawEnd =
            boundedSpeechEnd + trailingPadding
        let duration = max(
            rawEnd - rawStart,
            0
        )

        guard duration >= minimumDurationSeconds,
              duration <= maximumDuration + 0.000_001 else {
            return
        }

        let text = segments
            .map {
                $0.text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let preview: String
        if text.count > 240 {
            let index = text.index(
                text.startIndex,
                offsetBy: 237
            )
            preview = String(text[..<index]) + "…"
        } else {
            preview = text
        }

        let wordCount = text.split(
            whereSeparator: { $0.isWhitespace }
        ).count

        let confidences = segments
            .map(\.confidence)
            .filter { $0 > 0 }
        let averageConfidence: Float?
        if confidences.isEmpty {
            averageConfidence = nil
        } else {
            averageConfidence =
                confidences.reduce(0, +)
                / Float(confidences.count)
        }

        candidates.append(
            LocalClipCandidate(
                sourceRange: EditTimeRange(
                    startSeconds: rawStart,
                    durationSeconds: duration
                ),
                transcriptPreview: preview,
                wordCount: wordCount,
                averageConfidence: averageConfidence,
                segmentIDs: segments.map(\.id)
            )
        )
    }
}
