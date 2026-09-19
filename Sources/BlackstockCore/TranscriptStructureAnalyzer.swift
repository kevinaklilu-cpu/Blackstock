import Foundation

public struct TranscriptStructureSnapshot: Codable, Sendable, Equatable {
    public let firstSpeechStartSeconds: Double?
    public let spokenDurationSeconds: Double
    public let longestInterSegmentGapSeconds: Double?
    public let gapsAtLeastTwoSeconds: Int
    public let wordsInFirstThirtySeconds: Int
    public let totalWordCount: Int
    public let segmentCount: Int
    public let analyzedAt: Date

    public init(
        firstSpeechStartSeconds: Double?,
        spokenDurationSeconds: Double,
        longestInterSegmentGapSeconds: Double?,
        gapsAtLeastTwoSeconds: Int,
        wordsInFirstThirtySeconds: Int,
        totalWordCount: Int,
        segmentCount: Int,
        analyzedAt: Date
    ) {
        self.firstSpeechStartSeconds = firstSpeechStartSeconds
        self.spokenDurationSeconds = max(spokenDurationSeconds, 0)
        self.longestInterSegmentGapSeconds = longestInterSegmentGapSeconds
        self.gapsAtLeastTwoSeconds = max(gapsAtLeastTwoSeconds, 0)
        self.wordsInFirstThirtySeconds = max(wordsInFirstThirtySeconds, 0)
        self.totalWordCount = max(totalWordCount, 0)
        self.segmentCount = max(segmentCount, 0)
        self.analyzedAt = analyzedAt
    }

    public var factualSummary: [String] {
        var facts: [String] = []
        if let firstSpeechStartSeconds {
            facts.append(
                String(
                    format: "Erste erkannte Sprache beginnt bei %.2f s.",
                    firstSpeechStartSeconds
                )
            )
        }
        facts.append(
            String(
                format: "Erkannte Sprachsegmente umfassen zusammen %.2f s.",
                spokenDurationSeconds
            )
        )
        if let longestInterSegmentGapSeconds {
            facts.append(
                String(
                    format: "Längste gemessene Lücke zwischen Sprachsegmenten: %.2f s.",
                    longestInterSegmentGapSeconds
                )
            )
        }
        facts.append(
            "\(gapsAtLeastTwoSeconds) gemessene Lücken zwischen Sprachsegmenten sind mindestens 2 s lang."
        )
        facts.append(
            "\(wordsInFirstThirtySeconds) erkannte Wörter liegen in den ersten 30 s."
        )
        facts.append("\(totalWordCount) erkannte Wörter insgesamt.")
        return facts
    }
}

public struct TranscriptStructureAnalyzer: Sendable {
    public init() {}

    public func analyze(
        transcript: LocalTranscript,
        now: Date = Date()
    ) -> TranscriptStructureSnapshot {
        let ordered = transcript.segments.sorted {
            $0.startSeconds < $1.startSeconds
        }

        var spokenDuration = 0.0
        var longestGap: Double?
        var gapCount = 0
        var previousEnd: Double?

        for segment in ordered {
            spokenDuration += max(segment.durationSeconds, 0)

            if let previousEnd {
                let gap = max(segment.startSeconds - previousEnd, 0)
                longestGap = max(longestGap ?? 0, gap)
                if gap >= 2 {
                    gapCount += 1
                }
            }

            previousEnd = max(
                previousEnd ?? 0,
                segment.startSeconds + max(segment.durationSeconds, 0)
            )
        }

        let wordsInFirstThirty = ordered
            .filter { $0.startSeconds < 30 }
            .reduce(0) { $0 + Self.wordCount($1.text) }

        let totalWords = ordered.reduce(0) {
            $0 + Self.wordCount($1.text)
        }

        return .init(
            firstSpeechStartSeconds: ordered.first?.startSeconds,
            spokenDurationSeconds: spokenDuration,
            longestInterSegmentGapSeconds: longestGap,
            gapsAtLeastTwoSeconds: gapCount,
            wordsInFirstThirtySeconds: wordsInFirstThirty,
            totalWordCount: totalWords,
            segmentCount: ordered.count,
            analyzedAt: now
        )
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
