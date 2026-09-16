import Foundation
public actor TrendRepository {
    private let searcher: any YouTubeSearching
    private let engine: TrendEngine
    private let cache = TTLCache<String, YouTubeSearchPage>()
    public init(searcher: any YouTubeSearching, engine: TrendEngine = TrendEngine()) { self.searcher = searcher; self.engine = engine }
    public func trends(query: String, pageToken: String? = nil, channel: ChannelSnapshot? = nil) async throws -> TrendPage {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuery = clean.isEmpty ? (channel?.recentTopics.prefix(3).joined(separator: " ") ?? "YouTube") : clean
        let key = "\(effectiveQuery.lowercased())|\(pageToken ?? "first")"
        let raw: YouTubeSearchPage
        if let cached = await cache.value(for: key) { raw = cached } else { raw = try await searcher.search(query: effectiveQuery, pageToken: pageToken, maxResults: 30); await cache.insert(raw, for: key, ttl: 180) }
        return TrendPage(items: engine.rank(videos: raw.videos, channel: channel), nextPageToken: raw.nextPageToken)
    }
}
