#if os(macOS)
import Foundation
import NaturalLanguage

/// Uses Apple's local sentence-embedding model. A match is semantic similarity
/// evidence, not a claim that an image proves the spoken statement.
public actor SemanticSceneMatcher {
    public init() {}
    private static func endsSentence(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?…。！？".contains($0) } ?? false
    }
    public func select(transcript: LocalTranscript, reference: String,
                       sourceDuration: Double, maximumDuration: Double,
                       excluding: [EditTimeRange] = []) -> StorySceneSelection? {
        guard reference.count >= 15, maximumDuration.isFinite, maximumDuration >= 1,
              sourceDuration.isFinite, sourceDuration > 0,
              let language = NLLanguageRecognizer.dominantLanguage(for: reference),
              let sourceLanguage = NLLanguageRecognizer.dominantLanguage(for: transcript.text),
              language == sourceLanguage,
              let embedding = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        let segments = transcript.segments.filter {
            $0.confidence >= 0.5 && $0.startSeconds.isFinite && $0.durationSeconds.isFinite
                && $0.startSeconds >= 0 && $0.durationSeconds > 0
                && $0.startSeconds + $0.durationSeconds <= sourceDuration
        }.sorted { $0.startSeconds < $1.startSeconds }
        var best: StorySceneSelection?
        var bestDistance = 0.8
        // Sample the complete transcript, rather than only its opening.
        let strideSize = max(1, segments.count / 240)
        for index in stride(from: 0, to: segments.count, by: strideSize) {
            if Task.isCancelled { return nil }
            let first = segments[index]
            // A semantic match must not start halfway through a spoken phrase.
            if index > 0 {
                let previous = segments[index - 1]
                guard first.startSeconds - previous.startSeconds - previous.durationSeconds >= 0.25
                    || Self.endsSentence(previous.text) else { continue }
            }
            var window: [TranscriptSegment] = []
            for segment in segments[index...] {
                guard segment.startSeconds + segment.durationSeconds - first.startSeconds <= maximumDuration else { break }
                if let last = window.last, segment.startSeconds - last.startSeconds - last.durationSeconds > 1.5 { break }
                window.append(segment)
            }
            // Keep the last complete phrase that fits, rather than filling the
            // duration budget by cutting through the following sentence.
            while let last = window.last {
                let end = last.startSeconds + last.durationSeconds
                let next = segments.first { $0.startSeconds >= end - 0.001 && $0.startSeconds > last.startSeconds }
                if Self.endsSentence(last.text) || next == nil || (next!.startSeconds - end >= 0.25) { break }
                window.removeLast()
            }
            guard let last = window.last else { continue }
            let text = window.map(\.text).joined(separator: " ")
            let end = last.startSeconds + last.durationSeconds
            guard text.count >= 15, end - first.startSeconds >= 1,
                  !excluding.contains(where: { first.startSeconds < $0.endSeconds && end > $0.startSeconds }) else { continue }
            let distance = embedding.distance(between: reference, and: text)
            guard distance.isFinite, distance < bestDistance else { continue }
            bestDistance = distance
            best = StorySceneSelection(range: .init(startSeconds: first.startSeconds, durationSeconds: end - first.startSeconds),
                excerpt: text, explanation: "Lokale KI-Satzähnlichkeit · Leitvideo: „" + String(reference.prefix(140))
                    + "“ · Zusatzquelle: „" + String(text.prefix(140)) + "“. Bildinhalt zusätzlich prüfen.")
        }
        return best
    }
}
#endif
