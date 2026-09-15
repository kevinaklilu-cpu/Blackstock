import Foundation

public enum MomentEngine {
    private static let hookWords: Set<String> = [
        "aber","warum","plötzlich","problem","geheimnis","wirklich","unglaublich","niemand","wichtig","entscheidend","fehler","beste","schlimmste","überraschend","deshalb",
        "but","why","suddenly","problem","secret","actually","really","nobody","important","critical","mistake","best","worst","surprising","because"
    ]

    public static func rank(transcript: [TranscriptSegment], mediaDuration: Double, targetRange: ClosedRange<Double> = 18...55) -> [ClipMoment] {
        guard !transcript.isEmpty else { return [] }
        var candidates: [ClipMoment] = []
        for startIndex in transcript.indices {
            let start = transcript[startIndex].start
            var words: [String] = []
            var confidences: [Double] = []
            var end = start
            var endIndex = startIndex
            while endIndex < transcript.count {
                let segment = transcript[endIndex]
                end = segment.start + segment.duration
                words.append(segment.text)
                confidences.append(segment.confidence)
                let duration = end - start
                if duration >= targetRange.lowerBound {
                    candidates.append(makeMoment(start: start, end: min(mediaDuration, end), text: words.joined(separator: " "), confidences: confidences))
                }
                if duration >= targetRange.upperBound { break }
                endIndex += 1
            }
        }
        let sorted = candidates.sorted { lhs, rhs in lhs.score == rhs.score ? lhs.start < rhs.start : lhs.score > rhs.score }
        var selected: [ClipMoment] = []
        for candidate in sorted {
            let overlapsStrongly = selected.contains { existing in
                let overlap = max(0, min(existing.end, candidate.end) - max(existing.start, candidate.start))
                return overlap > min(existing.duration, candidate.duration) * 0.55
            }
            if !overlapsStrongly { selected.append(candidate) }
            if selected.count == 8 { break }
        }
        return selected
    }

    private static func makeMoment(start: Double, end: Double, text: String, confidences: [Double]) -> ClipMoment {
        let lower = text.lowercased()
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let hookHits = tokens.filter { hookWords.contains($0) }.count
        let hasNumber = tokens.contains { Double($0.replacingOccurrences(of: ",", with: ".")) != nil }
        let hasQuestion = text.contains("?")
        let avgConfidence = confidences.isEmpty ? 0.5 : confidences.reduce(0,+) / Double(confidences.count)
        let wordRate = Double(tokens.count) / max(1, end - start) * 60
        let densityScore = min(20, max(0, (wordRate - 75) / 6))
        let duration = end - start
        let durationScore = max(0, 18 - abs(duration - 32) * 0.55)
        let hookScore = min(28, Double(hookHits) * 7 + (hasQuestion ? 8 : 0) + (hasNumber ? 5 : 0))
        let confidenceScore = min(18, max(0, avgConfidence * 18))
        let sentenceStartBonus = text.first.map { String($0).uppercased() == String($0) ? 6.0 : 2.0 } ?? 0
        let score = min(100, 28 + densityScore + durationScore + hookScore + confidenceScore + sentenceStartBonus)
        var reasons: [String] = []
        if hookHits > 0 { reasons.append("starker sprachlicher Hook") }
        if hasQuestion { reasons.append("offene Frage erzeugt Spannung") }
        if hasNumber { reasons.append("konkrete Zahl erhöht Informationsdichte") }
        if wordRate >= 115 { reasons.append("hohe Informationsdichte") }
        if avgConfidence >= 0.7 { reasons.append("Transkript sicher erkannt") }
        if reasons.isEmpty { reasons.append("inhaltlich kompakter, vollständiger Abschnitt") }
        let preview = text.count > 220 ? String(text.prefix(217)) + "…" : text
        let titleWords = tokens.prefix(8).map { $0.capitalized }.joined(separator: " ")
        return ClipMoment(start: start, end: end, score: score, title: titleWords.isEmpty ? "Schnittmoment" : titleWords, rationale: reasons, previewText: preview, source: "Lokales Original")
    }
}
