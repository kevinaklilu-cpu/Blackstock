import Foundation

public struct LocalHighlightCandidateRanker: Sendable {
    public init() {}

    public func rank(
        _ candidates: [LocalClipCandidate],
        targetDurationSeconds: Double = 35
    ) -> [LocalClipCandidate] {
        let target = max(targetDurationSeconds, 15)
        return candidates.sorted { lhs, rhs in
            let left = score(lhs, targetDurationSeconds: target)
            let right = score(rhs, targetDurationSeconds: target)
            if left == right {
                return lhs.sourceRange.startSeconds
                    < rhs.sourceRange.startSeconds
            }
            return left > right
        }
    }

    private func score(
        _ candidate: LocalClipCandidate,
        targetDurationSeconds: Double
    ) -> Double {
        let duration = max(
            candidate.sourceRange.durationSeconds,
            1
        )
        let confidence = Double(
            candidate.averageConfidence ?? 0.75
        )
        let wordsPerSecond = Double(candidate.wordCount)
            / duration
        let speechDensity = min(
            max(wordsPerSecond / 2.8, 0),
            1
        )
        let durationFit = max(
            0,
            1 - abs(duration - targetDurationSeconds)
                / targetDurationSeconds
        )
        let openingBias = max(
            0,
            1 - candidate.sourceRange.startSeconds / 600
        )

        return confidence * 0.35
            + speechDensity * 0.30
            + durationFit * 0.25
            + openingBias * 0.10
    }
}
