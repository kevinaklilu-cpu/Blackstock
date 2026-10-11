import Foundation

public struct StoryPublicationDraft: Sendable {
    public let title: String
    public let description: String
    public let tags: [String]
    public let alternativeTitles: [String]
    public let alternativeDescriptions: [String]

    public init(title: String, description: String, tags: [String], alternativeTitles: [String], alternativeDescriptions: [String] = []) {
        self.title = title; self.description = description; self.tags = tags
        self.alternativeTitles = alternativeTitles; self.alternativeDescriptions = alternativeDescriptions
    }

    public static func make(sources: [YouTubeOpportunityCandidate], language: String,
                            excerpts: [String] = []) -> StoryPublicationDraft? {
        guard let lead = sources.first, sources.count > 1 else { return nil }
        let english = language.lowercased().hasPrefix("en")
        let matcher = StoryTopicMatcher()
        let topicWords = matcher.searchQuery(for: lead.title, excluding: lead.channelTitle)
        let topic = topicWords.isEmpty ? (english ? "The story" : "Das Thema") : topicWords.capitalized
        let alternatives = english
            ? ["\(topic): different voices, one story", "\(topic) — the key statements compared", "\(topic): what the different perspectives reveal"]
            : ["\(topic): verschiedene Stimmen, eine Story", "\(topic) – die zentralen Aussagen im Vergleich", "\(topic): die Perspektiven im Überblick"]
        var parts = [english
            ? "Selected moments from \(sources.count) videos bring together different perspectives on \(topic)."
            : "Ausgewählte Momente aus \(sources.count) Videos zeigen unterschiedliche Perspektiven auf \(topic)."]
        let evidence = Array(excerpts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(4))
        if !evidence.isEmpty {
            parts.append((english ? "Statements in this cut:\n" : "Aussagen in diesem Zusammenschnitt:\n")
                + evidence.map { "• „" + String($0.prefix(220)) + "“" }.joined(separator: "\n"))
        }
        parts.append((english ? "Sources used:\n" : "Verwendete Quellen:\n") + sources.map {
            $0.channelTitle + " – " + $0.title + "\nhttps://www.youtube.com/watch?v=" + $0.videoID
        }.joined(separator: "\n\n"))
        var seen = Set<String>()
        let tags = sources.flatMap { matcher.searchQuery(for: $0.title, excluding: $0.channelTitle).split(separator: " ").map(String.init) }
            .filter { seen.insert($0).inserted }.prefix(15)
        return .init(title: String(alternatives[0].prefix(100)), description: String(parts.joined(separator: "\n\n").prefix(5000)),
            tags: Array(tags), alternativeTitles: alternatives.map { String($0.prefix(100)) })
    }
}
