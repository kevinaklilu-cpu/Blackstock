import Foundation

struct TranscriptWord: Hashable, Codable {
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
}

struct CaptionCue: Identifiable, Hashable, Codable {
    let id: UUID
    let start: Double
    let end: Double
    let text: String

    init(id: UUID = UUID(), start: Double, end: Double, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    var duration: Double { max(0, end - start) }
    var charactersPerSecond: Double { duration > 0 ? Double(text.count) / duration : .infinity }
}

enum CaptionStyle: String, CaseIterable, Codable {
    case minimal = "Minimal"
    case creator = "Creator"
    case clean = "Clean"
}

struct CaptionQualityReport: Hashable {
    let score: Double
    let blockingIssues: [String]
    let warnings: [String]
    var passes: Bool { blockingIssues.isEmpty && score >= 90 }
}

struct CaptionEngine {
    let maxCharactersPerLine = 34
    let maxLines = 2
    let maxCharactersPerSecond = 20.0
    let minCueDuration = 0.65
    let maxCueDuration = 5.5

    func cues(from words: [TranscriptWord]) -> [CaptionCue] {
        let valid = words
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !valid.isEmpty else { return [] }

        var result: [CaptionCue] = []
        var bucket: [TranscriptWord] = []

        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            let text = punctuationAwareJoin(bucket.map(\.text))
            if !text.isEmpty {
                result.append(CaptionCue(start: first.start, end: max(last.end, first.start + minCueDuration), text: wrap(text)))
            }
            bucket.removeAll(keepingCapacity: true)
        }

        for word in valid {
            if let last = bucket.last {
                let gap = word.start - last.end
                let candidateText = punctuationAwareJoin((bucket + [word]).map(\.text))
                let candidateDuration = max(word.end - (bucket.first?.start ?? word.start), minCueDuration)
                let tooLong = candidateText.count > maxCharactersPerLine * maxLines
                let tooFast = Double(candidateText.count) / candidateDuration > maxCharactersPerSecond
                let sentenceBreak = gap > 0.55 || terminalPunctuation(last.text)
                if tooLong || tooFast || sentenceBreak || candidateDuration > maxCueDuration {
                    flush()
                }
            }
            bucket.append(word)
        }
        flush()
        return mergeTinyCues(result)
    }

    func qualityReport(cues: [CaptionCue], videoDuration: Double) -> CaptionQualityReport {
        guard !cues.isEmpty else {
            return .init(score: 0, blockingIssues: ["Keine Captions vorhanden."], warnings: [])
        }
        var score = 100.0
        var blocking: [String] = []
        var warnings: [String] = []
        var previousEnd = 0.0

        for cue in cues {
            if cue.start < -0.01 || cue.end > videoDuration + 0.1 || cue.end <= cue.start {
                blocking.append("Ungültiges Caption-Timing bei \(format(cue.start)).")
                score -= 20
            }
            if cue.start < previousEnd - 0.04 {
                blocking.append("Überlappende Caption-Cues bei \(format(cue.start)).")
                score -= 12
            }
            previousEnd = max(previousEnd, cue.end)
            if cue.charactersPerSecond > maxCharactersPerSecond {
                warnings.append("Caption bei \(format(cue.start)) ist zu schnell lesbar.")
                score -= min(8, (cue.charactersPerSecond - maxCharactersPerSecond) * 0.8)
            }
            if cue.text.split(separator: "\n").count > maxLines {
                blocking.append("Caption überschreitet zwei Zeilen.")
                score -= 10
            }
            if cue.text.split(separator: "\n").contains(where: { $0.count > maxCharactersPerLine + 4 }) {
                warnings.append("Caption-Zeile ist zu lang.")
                score -= 4
            }
            if cue.duration < 0.45 {
                warnings.append("Caption ist zu kurz eingeblendet.")
                score -= 5
            }
        }

        return .init(score: max(0, score), blockingIssues: Array(Set(blocking)), warnings: Array(Set(warnings)))
    }

    private func mergeTinyCues(_ cues: [CaptionCue]) -> [CaptionCue] {
        guard cues.count > 1 else { return cues }
        var out: [CaptionCue] = []
        for cue in cues {
            if cue.duration < minCueDuration, let last = out.last,
               cue.end - last.start <= maxCueDuration,
               (last.text + " " + cue.text).count <= maxCharactersPerLine * maxLines {
                out.removeLast()
                out.append(CaptionCue(start: last.start, end: cue.end, text: wrap(last.text.replacingOccurrences(of: "\n", with: " ") + " " + cue.text.replacingOccurrences(of: "\n", with: " "))))
            } else {
                out.append(cue)
            }
        }
        return out
    }

    private func punctuationAwareJoin(_ tokens: [String]) -> String {
        var text = ""
        for token in tokens {
            if text.isEmpty { text = token; continue }
            if token.first.map({ ",.!?:;)]}".contains($0) }) == true { text += token }
            else { text += " " + token }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wrap(_ text: String) -> String {
        guard text.count > maxCharactersPerLine else { return text }
        let words = text.split(separator: " ").map(String.init)
        var lines = ["", ""]
        for word in words {
            let firstCandidate = lines[0].isEmpty ? word : lines[0] + " " + word
            if firstCandidate.count <= maxCharactersPerLine || lines[1].isEmpty && lines[0].isEmpty {
                lines[0] = firstCandidate
            } else {
                let secondCandidate = lines[1].isEmpty ? word : lines[1] + " " + word
                lines[1] = secondCandidate
            }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func terminalPunctuation(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".!?".contains(last)
    }

    private func format(_ seconds: Double) -> String {
        String(format: "%.2fs", seconds)
    }
}

struct RenderQualityReport: Hashable {
    let captionReport: CaptionQualityReport?
    let sourceReadable: Bool
    let durationMatches: Bool
    let audioPresentWhenExpected: Bool
    let dimensionsValid: Bool
    let frameRateValid: Bool
    let errors: [String]

    var passes: Bool {
        errors.isEmpty && sourceReadable && durationMatches && audioPresentWhenExpected && dimensionsValid && frameRateValid && (captionReport?.passes ?? true)
    }
}
