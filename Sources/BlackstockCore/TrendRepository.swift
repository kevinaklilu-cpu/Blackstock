import Foundation

public actor TrendRepository {
    private let provider: any YouTubeFeedProviding
    private let engine: TrendEngine
    private let cache = TTLCache<String, YouTubeSearchPage>()

    public init(provider: any YouTubeFeedProviding, engine: TrendEngine = TrendEngine()) {
        self.provider = provider
        self.engine = engine
    }

    public func trends(query: String, regionCode: String? = nil, pageToken: String? = nil, channel: ChannelSnapshot? = nil) async throws -> TrendPage {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(clean.lowercased())|\((regionCode ?? "").uppercased())|\(pageToken ?? "first")"
        let raw: YouTubeSearchPage
        if let cached = await cache.value(for: key) {
            raw = cached
        } else {
            raw = clean.isEmpty
                ? try await provider.popular(regionCode: regionCode, pageToken: pageToken, maxResults: 35)
                : try await provider.search(query: clean, pageToken: pageToken, maxResults: 35)
            await cache.insert(raw, for: key, ttl: clean.isEmpty ? 300 : 180)
        }
        return TrendPage(items: engine.rank(videos: raw.videos, channel: channel), nextPageToken: raw.nextPageToken)
    }
}
