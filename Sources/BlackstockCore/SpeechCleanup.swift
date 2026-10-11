#if os(macOS)
import Foundation

public enum SpeechCleanupReason: String, Codable, Sendable {
    case fillerWord
    case longPause

    public var germanTitle: String {
        switch self {
        case .fillerWord: return "Füllwort"
        case .longPause: return "Lange Pause"
        }
    }
}

public struct SpeechCleanupSuggestion: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let outputRange: EditTimeRange
    public let reason: SpeechCleanupReason
    public let evidence: String

    public init(
        id: UUID = UUID(),
        outputRange: EditTimeRange,
        reason: SpeechCleanupReason,
        evidence: String
    ) {
        self.id = id
        self.outputRange = outputRange
        self.reason = reason
        self.evidence = evidence
    }
}

public struct SpeechCleanupPlan: Sendable, Equatable {
    public let suggestions: [SpeechCleanupSuggestion]

    public init(suggestions: [SpeechCleanupSuggestion]) {
        self.suggestions = suggestions
    }

    public var savedSeconds: Double {
        suggestions.reduce(0) { $0 + $1.outputRange.durationSeconds }
    }
}

public struct LocalSpeechCleanupPlanner: Sendable {
    private let fillerWords: Set<String> = [
        "äh", "ähm", "hm", "hmm", "uh", "um", "erm"
    ]

    public init() {}

    public func plan(
        transcript: LocalTranscript,
        outputDurationSeconds: Double
    ) -> SpeechCleanupPlan {
        let duration = max(outputDurationSeconds, 0)
        guard duration > 1 else { return SpeechCleanupPlan(suggestions: []) }

        let ordered = transcript.segments.sorted {
            $0.startSeconds < $1.startSeconds
        }
        var suggestions: [SpeechCleanupSuggestion] = []

        for segment in ordered {
            let normalized = segment.text
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            guard fillerWords.contains(normalized) else { continue }
            let start = max(segment.startSeconds - 0.03, 0)
            let end = min(
                segment.startSeconds + segment.durationSeconds + 0.03,
                duration
            )
            guard end - start >= 0.08 else { continue }
            suggestions.append(.init(
                outputRange: .init(
                    startSeconds: start,
                    durationSeconds: end - start
                ),
                reason: .fillerWord,
                evidence: segment.text
            ))
        }

        for pair in zip(ordered, ordered.dropFirst()) {
            let gapStart = pair.0.startSeconds + pair.0.durationSeconds
            let gapEnd = pair.1.startSeconds
            let gap = gapEnd - gapStart
            guard gap >= 1.2 else { continue }

            // Keep a natural breath on both sides of every automatic cut.
            let cutStart = max(gapStart + 0.25, 0)
            let cutEnd = min(gapEnd - 0.25, duration)
            guard cutEnd - cutStart >= 0.2 else { continue }
            suggestions.append(.init(
                outputRange: .init(
                    startSeconds: cutStart,
                    durationSeconds: cutEnd - cutStart
                ),
                reason: .longPause,
                evidence: String(format: "%.1f s Pause", gap)
            ))
        }

        let safeLimit = duration * 0.3
        var accepted: [SpeechCleanupSuggestion] = []
        var removed = 0.0
        for suggestion in suggestions.sorted(by: {
            $0.outputRange.startSeconds < $1.outputRange.startSeconds
        }).prefix(30) {
            guard removed + suggestion.outputRange.durationSeconds <= safeLimit else {
                continue
            }
            accepted.append(suggestion)
            removed += suggestion.outputRange.durationSeconds
        }
        return SpeechCleanupPlan(suggestions: accepted)
    }
}

public extension EditTimelinePlan {
    /// Maps an output-timeline range back to one or more source ranges. This
    /// keeps audio and video locked to the same EditGraph operations.
    func sourceRanges(forOutputRange requested: EditTimeRange) -> [EditTimeRange] {
        let outputStart = max(requested.startSeconds, 0)
        let outputEnd = min(requested.endSeconds, outputDurationSeconds)
        guard outputEnd - outputStart > 0.001 else { return [] }

        var outputCursor = 0.0
        var result: [EditTimeRange] = []
        for sourceRange in sourceRanges {
            let spanStart = outputCursor
            let spanEnd = outputCursor + sourceRange.durationSeconds
            let intersectionStart = max(outputStart, spanStart)
            let intersectionEnd = min(outputEnd, spanEnd)
            if intersectionEnd - intersectionStart > 0.001 {
                result.append(.init(
                    startSeconds: sourceRange.startSeconds
                        + intersectionStart - spanStart,
                    durationSeconds: intersectionEnd - intersectionStart
                ))
            }
            outputCursor = spanEnd
        }
        return result
    }
}
#endif
