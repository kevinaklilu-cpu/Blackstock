import Foundation
import NaturalLanguage

public extension StoryPublicationDraft {
    /// Extractive proposals are grounded in this cut, never copied from the source title.
    static func forClip(transcript: LocalTranscript?, sourceURL: URL?, start: Double,
                        duration: Double, isShort: Bool) -> StoryPublicationDraft {
        let text = (transcript?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.split(whereSeparator: \.isWhitespace).count >= 4 { sentences.append(sentence) }
            return sentences.count < 120
        }
        func title(_ sentence: String) -> String {
            let words = sentence.split(whereSeparator: \.isWhitespace)
            var result = ""
            for word in words {
                let next = result.isEmpty ? String(word) : result + " " + word
                if next.count > 90 { break }
                result = next
            }
            return result
        }
        var seen = Set<String>()
        let options = sentences.sorted { lhs, rhs in
            func score(_ s: String) -> Int {
                (s.contains("?") ? 4 : 0) + (s.rangeOfCharacter(from: .decimalDigits) != nil ? 2 : 0)
                    + (s.count <= 90 ? 3 : 0)
            }
            return score(lhs) > score(rhs)
        }.map(title).filter { !$0.isEmpty && seen.insert($0).inserted }
        let selected = options.first ?? "Titel für diesen Ausschnitt ergänzen"
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var keywords: [String] = []
        var unique = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
                let word = String(text[range])
                if tag == .noun, word.count >= 3, unique.insert(word.lowercased()).inserted { keywords.append(word) }
                return keywords.count < 15
            }
        func time(_ seconds: Double) -> String { String(format: "%d:%02d", Int(max(0, seconds)) / 60, Int(max(0, seconds)) % 60) }
        let excerpt = sentences.prefix(4).joined(separator: " ")
        var description = excerpt.isEmpty ? "Beschreibung des ausgewählten Moments ergänzen." : excerpt
        description += "\n\n" + (isShort ? "Short" : "Video") + " · Ausschnitt " + time(start) + "–" + time(start + duration)
        if let sourceURL { description += "\nQuelle: " + sourceURL.absoluteString }
        return .init(title: selected, description: String(description.prefix(5000)), tags: keywords,
            alternativeTitles: Array(options.prefix(3)))
    }
}
