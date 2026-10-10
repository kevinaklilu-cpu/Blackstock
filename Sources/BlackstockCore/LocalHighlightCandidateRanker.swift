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

    /// Suppress near-duplicate excerpts while preserving ranking order.
    public func distinct(_ ranked: [LocalClipCandidate], limit: Int) -> [LocalClipCandidate] {
        var selected: [LocalClipCandidate] = []
        guard limit > 0 else { return [] }
        for candidate in ranked where candidate.sourceRange.durationSeconds > 0 {
            let range = candidate.sourceRange
            guard !selected.contains(where: {
                let other = $0.sourceRange
                let overlap = max(0, min(range.endSeconds, other.endSeconds) - max(range.startSeconds, other.startSeconds))
                return overlap / min(range.durationSeconds, other.durationSeconds) > 0.6
            }) else { continue }
            selected.append(candidate)
            if selected.count == limit { break }
        }
        return selected
    }

    private func score(
        _ candidate: LocalClipCandidate,
        targetDurationSeconds: Double
    ) -> Double {
        if candidate.wordCount == 0, let visual = candidate.visualActivityScore { return visual }
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
        let hookStrength = transcriptHookStrength(
            candidate.transcriptPreview
        )

        let completeEnding = candidate.transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            .last.map { ".!?…。！？".contains($0) } == true ? 1.0 : 0.0
        return confidence * 0.35 + speechDensity * 0.25
            + hookStrength * 0.25 + completeEnding * 0.15
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
