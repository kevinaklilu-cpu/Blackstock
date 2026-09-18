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

    public init(
        videoID: String,
        title: String,
        channelID: String,
        channelTitle: String,
        publishedAt: Date?,
        thumbnailURL: URL?,
        query: String,
        retrievedAt: Date
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
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        c.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "q", value: query),
            .init(name: "maxResults", value: String(min(max(maxResults, 1), 25))),
            .init(name: "order", value: "date")
        ]
        let data = try await perform(c.url!, session: session)
        let response = try JSONDecoder.youtube.decode(SearchListResponse.self, from: data)
        return response.items.compactMap { item in
            guard let videoID = item.id.videoId else { return nil }
            return YouTubeOpportunityCandidate(
                videoID: videoID,
                title: item.snippet.title,
                channelID: item.snippet.channelId,
                channelTitle: item.snippet.channelTitle,
                publishedAt: item.snippet.publishedAt,
                thumbnailURL: item.snippet.thumbnails?.medium?.url ?? item.snippet.thumbnails?.defaultImage?.url,
                query: query,
                retrievedAt: now
            )
        }
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
