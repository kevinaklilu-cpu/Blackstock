import Foundation

public struct TrendEngine: Sendable {
    public init() {}
    public func rank(videos: [VideoMetric], channel: ChannelSnapshot?) -> [TrendSignal] {
        let vphMedian = median(videos.map(\.viewsPerHour).filter { $0.isFinite && $0 > 0 })
        return videos.map { score(video: $0, channel: channel, marketMedianVPH: max(vphMedian, 1)) }
            .sorted { $0.rankValue == $1.rankValue ? $0.video.publishedAt > $1.video.publishedAt : $0.rankValue > $1.rankValue }
    }
    private func score(video: VideoMetric, channel: ChannelSnapshot?, marketMedianVPH: Double) -> TrendSignal {
        let velocityRatio = video.viewsPerHour / marketMedianVPH
        let freshness = max(0, 1 - min(video.ageHours, 168) / 168)
        let engagement = engagementRate(video)
        let channelFit = channel.map { topicSimilarity(title: video.title, tags: video.tags, recentTopics: $0.recentTopics) } ?? 0.5
        let channelRelativeVelocity = channel.map { video.viewsPerHour / max($0.medianViewsPerHour, 1) } ?? velocityRatio
        let velocityComponent = clamp(log2(max(velocityRatio, 0.25)) / 4 + 0.5)
        let relativeComponent = clamp(log2(max(channelRelativeVelocity, 0.25)) / 4 + 0.5)
        let engagementComponent = clamp(engagement * 10)
        let rank = 0.36 * velocityComponent + 0.22 * relativeComponent + 0.17 * freshness + 0.15 * channelFit + 0.10 * engagementComponent
        var reasons: [TrendReason] = []
        if velocityRatio >= 2.5 { reasons.append(.init(key: "velocity", label: "Wächst deutlich schneller als ähnliche Videos", strength: .high)) }
        else if velocityRatio >= 1.35 { reasons.append(.init(key: "velocity", label: "Überdurchschnittliche aktuelle Dynamik", strength: .medium)) }
        if freshness >= 0.75 { reasons.append(.init(key: "fresh", label: "Sehr frisch veröffentlicht", strength: .medium)) }
        if channelFit >= 0.66 { reasons.append(.init(key: "fit", label: "Passt zu Themen deines Kanals", strength: channelFit >= 0.82 ? .high : .medium)) }
        if engagement >= 0.055 { reasons.append(.init(key: "engagement", label: "Starke sichtbare Interaktion", strength: .medium)) }
        let format = recommendFormat(video: video, channelFit: channelFit, velocityRatio: velocityRatio)
        if format == .short && video.format == .longform { reasons.append(.init(key: "repurpose", label: "Gutes Ausgangsmaterial für einen fokussierten Short", strength: .medium)) }
        else if format == .longform { reasons.append(.init(key: "longform", label: "Thema trägt eher ein längeres Video", strength: .medium)) }
        if reasons.isEmpty { reasons.append(.init(key: "baseline", label: "Relevant durch Kombination aus Aktualität und Nachfrage", strength: .low)) }
        return TrendSignal(video: video, reasons: Array(reasons.prefix(3)), recommendedFormat: format, rankValue: rank, topic: primaryTopic(video))
    }
    private func recommendFormat(video: VideoMetric, channelFit: Double, velocityRatio: Double) -> VideoFormat {
        if video.format == .longform && video.durationSeconds >= 360 && velocityRatio >= 1.35 { return .short }
        if video.durationSeconds >= 480 && channelFit >= 0.62 { return .longform }
        return video.format
    }
    private func primaryTopic(_ video: VideoMetric) -> String {
        if let first = video.tags.first, !first.isEmpty { return first }
        return tokenize(video.title).prefix(3).joined(separator: " ")
    }
    private func engagementRate(_ video: VideoMetric) -> Double {
        guard video.viewCount > 0 else { return 0 }
        return Double((video.likeCount ?? 0) + (video.commentCount ?? 0)) / Double(video.viewCount)
    }
    private func topicSimilarity(title: String, tags: [String], recentTopics: [String]) -> Double {
        guard !recentTopics.isEmpty else { return 0.5 }
        let candidate = Set(tokenize(([title] + tags).joined(separator: " ")))
        let recent = Set(tokenize(recentTopics.joined(separator: " ")))
        guard !candidate.isEmpty, !recent.isEmpty else { return 0.5 }
        let union = candidate.union(recent).count
        return union == 0 ? 0.5 : clamp(Double(candidate.intersection(recent).count) / Double(union) * 3.2)
    }
    private func tokenize(_ text: String) -> [String] {
        let stop: Set<String> = ["der","die","das","und","oder","mit","für","von","the","and","for","with","this","that","you","your","ist","ein","eine","auf","in"]
        return text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 && !stop.contains($0) }
    }
    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 1 }
        let sorted = values.sorted(), mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}
