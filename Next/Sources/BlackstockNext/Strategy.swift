import Foundation
import CoreGraphics

enum OutputFormatPreference: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatisch"
    case short = "Short 9:16"
    case video = "Video 16:9"

    var id: String { rawValue }
}

struct FormatRecommendation: Hashable {
    let portrait: Bool
    let label: String
    let reason: String
}

struct FormatRecommendationEngine {
    func recommend(source: SourceProbe, clip: ClipCandidate) -> FormatRecommendation {
        let sourcePortrait = source.naturalSize.height > source.naturalSize.width * 1.08
        if sourcePortrait {
            return .init(portrait: true, label: "Short 9:16", reason: "Die Quelle ist bereits hochkant; Blackstock erhält die natürliche Bildsprache.")
        }
        if clip.duration <= 75,
           clip.signals.hook >= 0.62,
           clip.signals.contextIndependence >= 0.60 {
            return .init(portrait: true, label: "Short 9:16", reason: "Kurzer, eigenständiger Moment mit schnellem Hook – geeignet für Discovery.")
        }
        return .init(portrait: false, label: "Video 16:9", reason: "Der Ausschnitt braucht mehr Raum und Kontext; Querformat erhält mehr Information.")
    }
}

struct PackagingGenerator {
    func concepts(for clip: ClipCandidate, dna: ChannelDNA?, sourceTitle: String) -> [PackagingConcept] {
        let topic = bestTopic(dna: dna, sourceTitle: sourceTitle, transcript: clip.transcript)
        let quote = strongestPhrase(in: clip.transcript)
        let promise = viewerPromise(topic: topic, quote: quote)
        return [
            .init(
                angle: .curiosity,
                title: "Warum \(topic) gerade viel wichtiger ist, als es wirkt",
                thumbnailPromise: shortThumbnail(quote.isEmpty ? "Was steckt dahinter?" : quote),
                viewerPromise: promise
            ),
            .init(
                angle: .outcome,
                title: "Der entscheidende Punkt bei \(topic)",
                thumbnailPromise: "DAS IST DER PUNKT",
                viewerPromise: promise
            ),
            .init(
                angle: .conflict,
                title: "Das Problem mit \(topic), das viele übersehen",
                thumbnailPromise: "DAS PROBLEM",
                viewerPromise: promise
            ),
            .init(
                angle: .surprise,
                title: "Damit hat bei \(topic) kaum jemand gerechnet",
                thumbnailPromise: "SO NICHT ERWARTET",
                viewerPromise: promise
            )
        ]
    }

    private func bestTopic(dna: ChannelDNA?, sourceTitle: String, transcript: String) -> String {
        if let keyword = dna?.topicKeywords.first, !keyword.isEmpty { return display(keyword) }
        let sourceWords = sourceTitle
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        if let first = sourceWords.first { return first }
        let words = transcript
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 5 }
        return display(words.first ?? "diesem Thema")
    }

    private func strongestPhrase(in transcript: String) -> String {
        let sentences = transcript
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 12 }
        let ranked = sentences.sorted { lhs, rhs in
            phraseStrength(lhs) > phraseStrength(rhs)
        }
        return ranked.first ?? ""
    }

    private func phraseStrength(_ value: String) -> Double {
        let lower = value.lowercased()
        let trigger = ["aber", "problem", "warum", "wichtig", "nie", "niemand", "ergebnis", "but", "why", "problem", "never", "actually", "result"]
        return Double(min(value.count, 70)) / 70 + Double(trigger.filter { lower.contains($0) }.count) * 0.35
    }

    private func viewerPromise(topic: String, quote: String) -> String {
        if !quote.isEmpty {
            return "Der Zuschauer versteht in einem kompakten Ausschnitt, warum \(topic) relevant ist und bekommt den konkreten Kernpunkt: \(quote)."
        }
        return "Der Zuschauer bekommt den stärksten eigenständigen Kernpunkt zu \(topic) ohne unnötige Einleitung."
    }

    private func shortThumbnail(_ value: String) -> String {
        let words = value.split(separator: " ").prefix(5).map(String.init)
        let joined = words.joined(separator: " ")
        return joined.count > 32 ? String(joined.prefix(32)) : joined.uppercased()
    }

    private func display(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }
}

struct OpportunityExplainer {
    func reasons(_ opportunity: Opportunity) -> [String] {
        var values: [String] = []
        if opportunity.relevance >= 0.72 { values.append("Hoher Fit zur Channel DNA") }
        else if opportunity.relevance >= 0.45 { values.append("Mittlerer Fit zur Channel DNA") }
        if opportunity.momentum >= 0.70 { values.append("Sehr hohe aktuelle Geschwindigkeit") }
        else if opportunity.momentum >= 0.45 { values.append("Steigende aktuelle Geschwindigkeit") }
        let hours = max(1, Date().timeIntervalSince(opportunity.publishedAt) / 3600)
        let vph = Double(opportunity.viewCount) / hours
        if vph >= 1_000 { values.append("\(compact(Int(vph))) Views/Stunde") }
        if values.isEmpty { values.append("Relevanz und Momentum werden gemeinsam bewertet") }
        return values
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }
}
