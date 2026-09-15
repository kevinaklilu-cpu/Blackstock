import Foundation

struct ChannelIdentity: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var description: String
    var primaryTopic: String
    var language: String
}

struct ChannelVideoProfile: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let description: String
    let publishedAt: Date
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    let durationSeconds: Double
    let tags: [String]
}

struct ChannelDNA: Hashable, Codable {
    let channelID: String
    var primaryTopic: String
    var topicKeywords: [String]
    var preferredDuration: ClosedRange<Double>
    var language: String
    var evidenceCount: Int
}

struct Opportunity: Identifiable, Hashable, Codable {
    let id: String
    let videoID: String
    let channelTitle: String
    let title: String
    let description: String
    let publishedAt: Date
    let viewCount: Int
    let durationSeconds: Double
    let relevance: Double
    let momentum: Double

    var score: Double {
        max(0, min(100, (relevance * 0.62 + momentum * 0.38) * 100))
    }
}

enum SourceKind: String, CaseIterable, Codable {
    case youtubeReference
    case localOwned
    case localLicensed
}

enum RightsDecision: Equatable {
    case youtubeNativeRemix
    case localExportAllowed
    case analysisOnly(reason: String)
}

struct SourceDescriptor: Hashable {
    let kind: SourceKind
    let userConfirmedRights: Bool
}

struct RightsPolicy {
    func decision(for source: SourceDescriptor) -> RightsDecision {
        switch source.kind {
        case .youtubeReference:
            return .youtubeNativeRemix
        case .localOwned, .localLicensed:
            return source.userConfirmedRights
                ? .localExportAllowed
                : .analysisOnly(reason: "Lokaler Export erfordert eine bestätigte Nutzungsberechtigung.")
        }
    }
}

struct ClipSignals: Hashable, Codable {
    var hook: Double
    var payoff: Double
    var contextIndependence: Double
    var informationDensity: Double
    var emotionalChange: Double
    var sentenceBoundaryQuality: Double
    var visualActivity: Double
    var silencePenalty: Double

    func normalized() -> ClipSignals {
        func c(_ value: Double) -> Double { max(0, min(1, value)) }
        return .init(
            hook: c(hook),
            payoff: c(payoff),
            contextIndependence: c(contextIndependence),
            informationDensity: c(informationDensity),
            emotionalChange: c(emotionalChange),
            sentenceBoundaryQuality: c(sentenceBoundaryQuality),
            visualActivity: c(visualActivity),
            silencePenalty: c(silencePenalty)
        )
    }
}

struct ClipCandidate: Identifiable, Hashable, Codable {
    let id: UUID
    var start: Double
    var end: Double
    var transcript: String
    var signals: ClipSignals

    init(id: UUID = UUID(), start: Double, end: Double, transcript: String, signals: ClipSignals) {
        self.id = id
        self.start = start
        self.end = end
        self.transcript = transcript
        self.signals = signals
    }

    var duration: Double { max(0, end - start) }
}

struct ClipEvaluation: Hashable {
    let candidate: ClipCandidate
    let score: Double
    let reasons: [String]
}

struct ClipIntelligenceEngine {
    func evaluate(_ candidate: ClipCandidate, targetDuration: ClosedRange<Double>) -> ClipEvaluation {
        let s = candidate.signals.normalized()
        var score =
            s.hook * 0.20 +
            s.payoff * 0.18 +
            s.contextIndependence * 0.16 +
            s.informationDensity * 0.14 +
            s.emotionalChange * 0.10 +
            s.sentenceBoundaryQuality * 0.10 +
            s.visualActivity * 0.07 +
            (1 - s.silencePenalty) * 0.05

        var reasons: [String] = []
        if s.hook >= 0.75 { reasons.append("starker Einstieg") }
        if s.payoff >= 0.75 { reasons.append("klarer Payoff") }
        if s.contextIndependence >= 0.75 { reasons.append("ohne langen Kontext verständlich") }
        if s.sentenceBoundaryQuality >= 0.8 { reasons.append("saubere Satzgrenzen") }

        if !targetDuration.contains(candidate.duration) {
            let distance: Double
            if candidate.duration < targetDuration.lowerBound {
                distance = targetDuration.lowerBound - candidate.duration
            } else {
                distance = candidate.duration - targetDuration.upperBound
            }
            score -= min(0.25, distance / 120)
            reasons.append("Dauer weicht vom Zielbereich ab")
        }

        if candidate.transcript.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            score -= 0.15
            reasons.append("zu wenig eigenständiger Inhalt")
        }

        return ClipEvaluation(
            candidate: candidate,
            score: max(0, min(100, score * 100)),
            reasons: reasons
        )
    }

    func rank(_ candidates: [ClipCandidate], targetDuration: ClosedRange<Double>) -> [ClipEvaluation] {
        candidates
            .map { evaluate($0, targetDuration: targetDuration) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.candidate.start < rhs.candidate.start }
                return lhs.score > rhs.score
            }
    }
}

struct ChannelDNAEngine {
    private let stopWords: Set<String> = [
        "und", "oder", "aber", "der", "die", "das", "ein", "eine", "mit", "für", "von", "auf", "ist", "im", "in",
        "the", "and", "or", "with", "for", "from", "this", "that", "you", "your", "video"
    ]

    func build(identity: ChannelIdentity, videos: [ChannelVideoProfile]) -> ChannelDNA {
        var frequency: [String: Double] = [:]
        var durations: [Double] = []

        for video in videos {
            let performanceWeight = max(1, log10(Double(max(10, video.viewCount))))
            durations.append(video.durationSeconds)
            let text = ([video.title, video.description] + video.tags).joined(separator: " ")
            for token in tokenize(text) where token.count >= 3 && !stopWords.contains(token) {
                frequency[token, default: 0] += performanceWeight
            }
        }

        let keywords = frequency
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map(\.key)

        let sortedDurations = durations.sorted()
        let lower = percentile(sortedDurations, p: 0.25) ?? 30
        let upper = percentile(sortedDurations, p: 0.75) ?? max(60, lower)
        let inferredTopic = keywords.prefix(3).joined(separator: " · ")

        return ChannelDNA(
            channelID: identity.id,
            primaryTopic: inferredTopic.isEmpty ? identity.primaryTopic : inferredTopic,
            topicKeywords: keywords,
            preferredDuration: max(15, lower)...max(max(30, lower), upper),
            language: identity.language,
            evidenceCount: videos.count
        )
    }

    func relevance(of text: String, to dna: ChannelDNA) -> Double {
        guard !dna.topicKeywords.isEmpty else { return 0.5 }
        let tokens = Set(tokenize(text))
        let matches = dna.topicKeywords.filter(tokens.contains).count
        return min(1, Double(matches) / Double(max(3, dna.topicKeywords.count / 2)))
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func percentile(_ sorted: [Double], p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[max(0, min(sorted.count - 1, index))]
    }
}
