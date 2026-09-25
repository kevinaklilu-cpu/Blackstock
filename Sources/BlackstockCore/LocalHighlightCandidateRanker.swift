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
        let hookStrength = transcriptHookStrength(
            candidate.transcriptPreview
        )

        return confidence * 0.25
            + speechDensity * 0.25
            + durationFit * 0.20
            + hookStrength * 0.20
            + openingBias * 0.10
    }

    private func transcriptHookStrength(_ text: String) -> Double {
        let normalized = text.lowercased()
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }
        let hookTerms = [
            "warum", "wie ", "so ", "fehler", "geheim", "überrasch", "niemals",
            "what", "why", "how ", "mistake", "secret", "surpris", "never"
        ]
        let termHits = hookTerms.filter { normalized.contains($0) }.count
        let punctuation = normalized.contains("?") || normalized.contains("!") ? 0.25 : 0
        let digit = normalized.rangeOfCharacter(from: .decimalDigits) != nil ? 0.15 : 0
        return min(Double(termHits) * 0.22 + punctuation + digit, 1)
    }
}
