import Foundation

/// Explainable lexical evidence, deliberately not a semantic or virality score.
public struct StoryTopicMatch: Sendable, Equatable {
    public let terms: [String]
    public let relevance: Double
    public var isRelated: Bool { !terms.isEmpty }
    public var explanation: String {
        terms.isEmpty
            ? "Keine gemeinsamen Themenbegriffe erkannt – manuell prüfen."
            : "Gemeinsame Begriffe: " + terms.prefix(4).joined(separator: ", ")
    }
}

public struct StoryTopicMatcher: Sendable {
    public init() {}

    public func searchQuery(for title: String, excluding channel: String = "") -> String {
        let meaningful = terms(title).subtracting(terms(channel))
        var seen = Set<String>()
        return title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { meaningful.contains($0) && seen.insert($0).inserted }
            .prefix(2).joined(separator: " ")
    }

    public func match(_ candidate: YouTubeOpportunityCandidate, to lead: YouTubeOpportunityCandidate) -> StoryTopicMatch {
        let reference = terms(lead.title).subtracting(terms(lead.channelTitle))
        let evidence = terms(candidate.title + " " + String((candidate.description ?? "").prefix(1500)))
        let shared = reference.intersection(evidence).sorted()
        return StoryTopicMatch(terms: shared, relevance: Double(shared.count) / Double(max(reference.count, 1)))
    }

    public func match(_ text: String, to reference: String) -> StoryTopicMatch {
        let source = terms(text)
        let target = terms(reference)
        let shared = source.intersection(target).sorted()
        let denominator = max(min(source.count, target.count), 1)
        return StoryTopicMatch(terms: shared,
            relevance: Double(shared.count) / Double(denominator))
    }

    private func terms(_ text: String) -> Set<String> {
        let ignored = Set("all sports sport news extended der die das den dem des ein eine einer einem einen eines und oder aber auch mit ohne für von vom zum zur aus bei nach vor über unter nicht nur noch schon wird werden wurde ist sind war waren hat haben hatte als auf im in am an es ich du er sie wir ihr mein meine dein seine dieser diese dieses dieses the a an and or but with without for from to of on in at is are was were be been this that these those it its you your we our how why what when where video videos short shorts official highlights highlight full best top new neu neue neuer neues heute today jetzt now watch ansehen amazing incredible compilation interview tutorial picking picks every world ultimate guide episode teil part viral trending trend must see erklärt erklärt einfach".split(separator: " ").map(String.init))
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        let normalizedIgnored = Set(ignored.map {
            $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        })
        return Set(normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !normalizedIgnored.contains($0)
                && $0.rangeOfCharacter(from: .letters) != nil })
    }
}

#if os(macOS)
public struct StorySceneSelection: Sendable, Equatable {
    public let range: EditTimeRange
    public let excerpt: String
    public let explanation: String
}

public struct StorySceneSelector: Sendable {
    public init() {}

    public func select(transcript: LocalTranscript, reference: String,
                       sourceDuration: Double, maximumDuration: Double) -> StorySceneSelection? {
        guard sourceDuration.isFinite, maximumDuration.isFinite,
              sourceDuration > 0, maximumDuration >= 1 else { return nil }
        let segments = transcript.segments.filter {
            $0.startSeconds.isFinite && $0.durationSeconds.isFinite
                && $0.startSeconds >= 0 && $0.durationSeconds > 0
                && $0.startSeconds + $0.durationSeconds <= sourceDuration
                && $0.confidence >= 0.5
        }.sorted { $0.startSeconds < $1.startSeconds }
        var best: StorySceneSelection?
        var bestScore = 0.0
        for (index, first) in segments.enumerated() {
            var window: [TranscriptSegment] = []
            for segment in segments[index...] {
                if segment.startSeconds + segment.durationSeconds - first.startSeconds > maximumDuration - 0.2 { break }
                if let last = window.last,
                   segment.startSeconds - last.startSeconds - last.durationSeconds > 1.5 { break }
                window.append(segment)
            }
            guard let last = window.last else { continue }
            let text = window.map(\.text).joined(separator: " ")
            let match = StoryTopicMatcher().match(text, to: reference)
            let start = max(0, first.startSeconds - 0.1)
            let end = min(sourceDuration, last.startSeconds + last.durationSeconds + 0.1)
            guard match.isRelated, end - start >= 1 else { continue }
            let score = Double(match.terms.count) + match.relevance
            guard score > bestScore else { continue }
            bestScore = score
            best = StorySceneSelection(range: .init(startSeconds: start, durationSeconds: end - start),
                excerpt: text, explanation: match.explanation)
        }
        return best
    }
}
#endif
