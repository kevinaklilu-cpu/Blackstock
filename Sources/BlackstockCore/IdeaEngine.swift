import Foundation

public struct IdeaEngine: Sendable {
    public init() {}
    public func ideas(from signals: [TrendSignal], limit: Int = 12) -> [ContentIdea] {
        let grouped = Dictionary(grouping: signals) { normalizedTopic($0.topic) }
        return grouped.compactMap { topic, items -> ContentIdea? in
            guard let lead = items.max(by: { $0.rankValue < $1.rankValue }) else { return nil }
            let formats = Dictionary(grouping: items, by: \.recommendedFormat).mapValues(\.count)
            let format = (formats[.short] ?? 0) > (formats[.longform] ?? 0) ? VideoFormat.short : .longform
            let evidence = Array(items.flatMap(\.reasons).map(\.label).reduce(into: [String]()) { result, value in if !result.contains(value) { result.append(value) } }.prefix(3))
            let working = makeWorkingTitle(topic: topic, lead: lead.video.title, format: format)
            return ContentIdea(id: topic, topic: topic, workingTitle: working, recommendedFormat: format, evidence: evidence, sourceVideoIDs: Array(items.map(\.video.id).prefix(5)))
        }.sorted { lhs, rhs in
            let l = signals.first(where: { normalizedTopic($0.topic) == lhs.topic })?.rankValue ?? 0
            let r = signals.first(where: { normalizedTopic($0.topic) == rhs.topic })?.rankValue ?? 0
            return l > r
        }.prefix(max(limit, 1)).map { $0 }
    }
    private func normalizedTopic(_ value: String) -> String { let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); return clean.isEmpty ? "thema" : clean }
    private func makeWorkingTitle(topic: String, lead: String, format: VideoFormat) -> String {
        if format == .short { return topic == "thema" ? lead : "\(topic.capitalized): der Kern in kurzer Form" }
        return topic == "thema" ? lead : "\(topic.capitalized): was gerade wirklich relevant ist"
    }
}
