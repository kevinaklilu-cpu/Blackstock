import Foundation

public struct YouTubeChannelIdentity: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let handle: String?
    public let avatarURL: URL?
    public let subscriberCount: Int?
    public let uploadsPlaylistID: String?

    public init(
        id: String,
        title: String,
        handle: String?,
        avatarURL: URL?,
        subscriberCount: Int?,
        uploadsPlaylistID: String?
    ) {
        self.id = id
        self.title = title
        self.handle = handle
        self.avatarURL = avatarURL
        self.subscriberCount = subscriberCount
        self.uploadsPlaylistID = uploadsPlaylistID
    }
}

public struct YouTubeOpportunityMetrics: Codable, Sendable, Equatable {
    public let viewCount: Int?
    public let likeCount: Int?
    public let commentCount: Int?
    public let channelSubscriberCount: Int?
    public let publishedAt: Date?
    public let retrievedAt: Date

    public init(
        viewCount: Int?,
        likeCount: Int?,
        commentCount: Int?,
        channelSubscriberCount: Int?,
        publishedAt: Date?,
        retrievedAt: Date
    ) {
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.channelSubscriberCount = channelSubscriberCount
        self.publishedAt = publishedAt
        self.retrievedAt = retrievedAt
    }

    public var ageHours: Double? {
        guard let publishedAt else { return nil }
        return max(retrievedAt.timeIntervalSince(publishedAt) / 3600, 0)
    }

    public var viewsPerHour: Double? {
        guard let views = viewCount, let hours = ageHours, hours >= 0.25 else { return nil }
        return Double(views) / hours
    }

    public var viewsPerSubscriber: Double? {
        guard let views = viewCount,
              let subscribers = channelSubscriberCount,
              subscribers > 0 else { return nil }
        return Double(views) / Double(subscribers)
    }

    public var likeRate: Double? {
        guard let likes = likeCount, let views = viewCount, views > 0 else { return nil }
        return Double(likes) / Double(views)
    }

    public var commentRate: Double? {
        guard let comments = commentCount, let views = viewCount, views > 0 else { return nil }
        return Double(comments) / Double(views)
    }

    public var missingSignals: [String] {
        var missing: [String] = []
        if viewCount == nil { missing.append("Views") }
        if likeCount == nil { missing.append("Likes") }
        if commentCount == nil { missing.append("Kommentare") }
        if channelSubscriberCount == nil { missing.append("Abonnentenzahl") }
        if publishedAt == nil { missing.append("Veröffentlichungszeit") }
        return missing
    }
}

public struct YouTubeOpportunityCandidate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let videoID: String
    public let title: String
    public let channelID: String
    public let channelTitle: String
    public let publishedAt: Date?
    public let thumbnailURL: URL?
    public let query: String
    public let retrievedAt: Date
    public let embeddable: Bool?
    public let metrics: YouTubeOpportunityMetrics

    public init(
        videoID: String,
        title: String,
        channelID: String,
        channelTitle: String,
        publishedAt: Date?,
        thumbnailURL: URL?,
        query: String,
        retrievedAt: Date,
        embeddable: Bool?,
        metrics: YouTubeOpportunityMetrics
    ) {
        self.id = videoID
        self.videoID = videoID
        self.title = title
        self.channelID = channelID
        self.channelTitle = channelTitle
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.query = query
        self.retrievedAt = retrievedAt
        self.embeddable = embeddable
        self.metrics = metrics
    }
}

public enum OpportunitySortMode: String, Codable, Sendable, CaseIterable {
    case newest
    case views
    case viewsPerHour
    case channelRelative

    public var germanTitle: String {
        switch self {
        case .newest: return "Neueste"
        case .views: return "Views"
        case .viewsPerHour: return "Views/Stunde"
        case .channelRelative: return "Kanalrelativ"
        }
    }

    public var germanExplanation: String {
        switch self {
        case .newest:
            return "Sortiert ausschließlich nach realem Veröffentlichungszeitpunkt."
        case .views:
            return "Sortiert ausschließlich nach dem von YouTube gemeldeten View Count."
        case .viewsPerHour:
            return "Views ÷ Stunden seit Veröffentlichung. Keine Prognose."
        case .channelRelative:
            return "Views ÷ öffentliche Abonnentenzahl des Quellkanals. Keine Prognose; Abonnentenzahlen können gerundet sein."
        }
    }
}

public extension Array where Element == YouTubeOpportunityCandidate {
    func sorted(by mode: OpportunitySortMode) -> [YouTubeOpportunityCandidate] {
        switch mode {
        case .newest:
            return sorted {
                ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
            }
        case .views:
            return sorted {
                ($0.metrics.viewCount ?? -1) > ($1.metrics.viewCount ?? -1)
            }
        case .viewsPerHour:
            return sorted {
                ($0.metrics.viewsPerHour ?? -1) > ($1.metrics.viewsPerHour ?? -1)
            }
        case .channelRelative:
            return sorted {
                ($0.metrics.viewsPerSubscriber ?? -1) > ($1.metrics.viewsPerSubscriber ?? -1)
            }
        }
    }
}

public enum YouTubeAPIError: Error, Equatable, Sendable {
    case invalidResponse
    case unauthorized
    case api(Int)
    case noChannel
}

public struct YouTubeAuthorizedClient: Sendable {
    public let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    public func myChannels(session: URLSession = .shared) async throws -> [YouTubeChannelIdentity] {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        c.queryItems = [
            .init(name: "part", value: "snippet,statistics,contentDetails"),
            .init(name: "mine", value: "true"),
            .init(name: "maxResults", value: "50")
        ]
        let data = try await perform(c.url!, session: session)
        let response = try JSONDecoder.youtube.decode(ChannelListResponse.self, from: data)
        return response.items.map {
            YouTubeChannelIdentity(
                id: $0.id,
                title: $0.snippet.title,
                handle: $0.snippet.customUrl,
                avatarURL: $0.snippet.thumbnails?.defaultImage?.url,
                subscriberCount: $0.statistics.flatMap { Int($0.subscriberCount ?? "") },
                uploadsPlaylistID: $0.contentDetails?.relatedPlaylists.uploads
            )
        }
    }

    public func firstOpportunityCandidates(
        query: String,
        maxResults: Int = 12,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> [YouTubeOpportunityCandidate] {
        var search = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        search.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "q", value: query),
            .init(name: "maxResults", value: String(min(max(maxResults, 1), 25))),
            .init(name: "order", value: "date")
        ]

        let searchData = try await perform(search.url!, session: session)
        let searchResponse = try JSONDecoder.youtube.decode(SearchListResponse.self, from: searchData)
        let searchItems = searchResponse.items.compactMap { item -> SearchItem? in
            item.id.videoId == nil ? nil : item
        }

        let videoIDs = searchItems.compactMap(\.id.videoId)
        let channelIDs = Array(Set(searchItems.map(\.snippet.channelId)))

        async let videoDetails = loadVideoDetails(ids: videoIDs, session: session)
        async let channelDetails = loadChannelSubscriberCounts(ids: channelIDs, session: session)
        let (videos, subscribers) = try await (videoDetails, channelDetails)

        return searchItems.compactMap { item in
            guard let videoID = item.id.videoId else { return nil }
            let video = videos[videoID]
            let metrics = YouTubeOpportunityMetrics(
                viewCount: video?.statistics.flatMap { Int($0.viewCount ?? "") },
                likeCount: video?.statistics.flatMap { Int($0.likeCount ?? "") },
                commentCount: video?.statistics.flatMap { Int($0.commentCount ?? "") },
                channelSubscriberCount: subscribers[item.snippet.channelId],
                publishedAt: item.snippet.publishedAt,
                retrievedAt: now
            )

            return YouTubeOpportunityCandidate(
                videoID: videoID,
                title: item.snippet.title,
                channelID: item.snippet.channelId,
                channelTitle: item.snippet.channelTitle,
                publishedAt: item.snippet.publishedAt,
                thumbnailURL: item.snippet.thumbnails?.medium?.url ?? item.snippet.thumbnails?.defaultImage?.url,
                query: query,
                retrievedAt: now,
                embeddable: video?.status?.embeddable,
                metrics: metrics
            )
        }
    }

    private func loadVideoDetails(
        ids: [String],
        session: URLSession
    ) async throws -> [String: VideoItem] {
        guard !ids.isEmpty else { return [:] }
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        c.queryItems = [
            .init(name: "part", value: "statistics,status"),
            .init(name: "id", value: ids.joined(separator: ","))
        ]
        let data = try await perform(c.url!, session: session)
        let response = try JSONDecoder.youtube.decode(VideoListResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.items.map { ($0.id, $0) })
    }

    private func loadChannelSubscriberCounts(
        ids: [String],
        session: URLSession
    ) async throws -> [String: Int] {
        guard !ids.isEmpty else { return [:] }
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        c.queryItems = [
            .init(name: "part", value: "statistics"),
            .init(name: "id", value: ids.joined(separator: ","))
        ]
        let data = try await perform(c.url!, session: session)
        let response = try JSONDecoder.youtube.decode(ChannelStatsListResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.items.compactMap {
            guard let value = Int($0.statistics.subscriberCount ?? "") else { return nil }
            return ($0.id, value)
        })
    }

    private func perform(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YouTubeAPIError.invalidResponse }
        if http.statusCode == 401 { throw YouTubeAPIError.unauthorized }
        guard 200..<300 ~= http.statusCode else { throw YouTubeAPIError.api(http.statusCode) }
        return data
    }
}

private struct ChannelListResponse: Decodable {
    let items: [ChannelItem]
}
private struct ChannelItem: Decodable {
    let id: String
    let snippet: ChannelSnippet
    let statistics: ChannelStatistics?
    let contentDetails: ChannelContentDetails?
}
private struct ChannelSnippet: Decodable {
    let title: String
    let customUrl: String?
    let thumbnails: ThumbnailSet?
}
private struct ChannelStatistics: Decodable {
    let subscriberCount: String?
}
private struct ChannelContentDetails: Decodable {
    let relatedPlaylists: RelatedPlaylists
}
private struct RelatedPlaylists: Decodable {
    let uploads: String?
}
private struct ChannelStatsListResponse: Decodable {
    let items: [ChannelStatsItem]
}
private struct ChannelStatsItem: Decodable {
    let id: String
    let statistics: ChannelStatistics
}

private struct VideoListResponse: Decodable {
    let items: [VideoItem]
}
private struct VideoItem: Decodable {
    let id: String
    let statistics: VideoStatistics?
    let status: VideoStatus?
}
private struct VideoStatistics: Decodable {
    let viewCount: String?
    let likeCount: String?
    let commentCount: String?
}
private struct VideoStatus: Decodable {
    let embeddable: Bool?
}

private struct ThumbnailSet: Decodable {
    let defaultImage: Thumbnail?
    let medium: Thumbnail?

    enum CodingKeys: String, CodingKey {
        case defaultImage = "default"
        case medium
    }
}
private struct Thumbnail: Decodable { let url: URL }

private struct SearchListResponse: Decodable { let items: [SearchItem] }
private struct SearchItem: Decodable {
    let id: SearchID
    let snippet: SearchSnippet
}
private struct SearchID: Decodable { let videoId: String? }
private struct SearchSnippet: Decodable {
    let publishedAt: Date?
    let channelId: String
    let title: String
    let channelTitle: String
    let thumbnails: ThumbnailSet?
}

private extension JSONDecoder {
    static var youtube: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
