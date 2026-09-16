import Foundation

public struct NicheCluster: Identifiable, Sendable, Equatable {
    public let id: String
    public let topic: String
    public let videoCount: Int
    public let creatorCount: Int
    public let medianViews: Double
    public let medianViewsPerHour: Double
    public let shortCount: Int
    public let longformCount: Int
    public let evidence: [TrendSignal]

    public init(id: String, topic: String, videoCount: Int, creatorCount: Int, medianViews: Double, medianViewsPerHour: Double, shortCount: Int, longformCount: Int, evidence: [TrendSignal]) {
        self.id = id
        self.topic = topic
        self.videoCount = videoCount
        self.creatorCount = creatorCount
        self.medianViews = medianViews
        self.medianViewsPerHour = medianViewsPerHour
        self.shortCount = shortCount
        self.longformCount = longformCount
        self.evidence = evidence
    }
}

public struct ResearchEngine: Sendable {
    public init() {}

    public func clusters(from signals: [TrendSignal], minimumVideos: Int = 2) -> [NicheCluster] {
        let groups = Dictionary(grouping: signals) { normalizedTopic($0.topic.isEmpty ? $0.video.title : $0.topic) }
        return groups.compactMap { key, values -> NicheCluster? in
            guard values.count >= minimumVideos else { return nil }
            let sorted = values.sorted { lhs, rhs in
                if lhs.rankValue == rhs.rankValue { return lhs.video.viewsPerHour > rhs.video.viewsPerHour }
                return lhs.rankValue > rhs.rankValue
            }
            let creators = Set(values.map(\.video.channelID)).count
            let views = median(values.map { Double($0.video.viewCount) })
            let velocity = median(values.map(\.video.viewsPerHour))
            let shorts = values.filter { $0.video.format == .short }.count
            return NicheCluster(
                id: key,
                topic: displayTopic(key, fallback: values.first?.topic ?? key),
                videoCount: values.count,
                creatorCount: creators,
                medianViews: views,
                medianViewsPerHour: velocity,
                shortCount: shorts,
                longformCount: values.count - shorts,
                evidence: Array(sorted.prefix(5))
            )
        }
        .sorted { lhs, rhs in
            if lhs.videoCount == rhs.videoCount { return lhs.medianViewsPerHour > rhs.medianViewsPerHour }
            return lhs.videoCount > rhs.videoCount
        }
    }

    private func normalizedTopic(_ value: String) -> String {
        let stop: Set<String> = ["der","die","das","und","oder","mit","für","von","the","and","for","with","this","that","you","your","video","shorts","short"]
        let tokens = value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) }
        return tokens.prefix(2).joined(separator: "-")
    }

    private func displayTopic(_ key: String, fallback: String) -> String {
        if key.isEmpty { return fallback.isEmpty ? "Thema" : fallback }
        return key.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
