import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct YouTubeSearchPage: Sendable {
    public let videos: [VideoMetric]
    public let nextPageToken: String?
    public init(videos: [VideoMetric], nextPageToken: String?) { self.videos = videos; self.nextPageToken = nextPageToken }
}

public protocol YouTubeFeedProviding: Sendable {
    func search(query: String, pageToken: String?, maxResults: Int) async throws -> YouTubeSearchPage
    func popular(regionCode: String?, pageToken: String?, maxResults: Int) async throws -> YouTubeSearchPage
}

public protocol YouTubeChannelProviding: Sendable {
    func channelSnapshot(reference: String) async throws -> ChannelSnapshot
}

public enum YouTubeAPIError: LocalizedError {
    case missingAPIKey, invalidResponse, channelNotFound, api(String)
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Für Live-Daten fehlt ein YouTube Data API Key."
        case .invalidResponse: return "YouTube hat eine unerwartete Antwort geliefert."
        case .channelNotFound: return "Der YouTube-Kanal wurde nicht gefunden."
        case .api(let message): return message
        }
    }
}

public struct YouTubeDataAPIClient: YouTubeFeedProviding, YouTubeChannelProviding {
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func search(query: String, pageToken: String? = nil, maxResults: Int = 30) async throws -> YouTubeSearchPage {
        try requireKey()
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        var items = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "order", value: "date"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(clampResults(maxResults))),
            URLQueryItem(name: "publishedAfter", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86400))),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let pageToken, !pageToken.isEmpty { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps.queryItems = items
        let (data, response) = try await session.data(from: comps.url!)
        try validate(data: data, response: response)
        let search = try JSONDecoder.youtube.decode(SearchResponse.self, from: data)
        let ids = search.items.map(\.id.videoId).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return YouTubeSearchPage(videos: [], nextPageToken: search.nextPageToken) }
        return YouTubeSearchPage(videos: try await fetchDetails(ids: ids), nextPageToken: search.nextPageToken)
    }

    public func popular(regionCode: String? = nil, pageToken: String? = nil, maxResults: Int = 30) async throws -> YouTubeSearchPage {
        try requireKey()
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        var items = [
            URLQueryItem(name: "part", value: "snippet,contentDetails,statistics"),
            URLQueryItem(name: "chart", value: "mostPopular"),
            URLQueryItem(name: "maxResults", value: String(clampResults(maxResults))),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let regionCode, !regionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append(URLQueryItem(name: "regionCode", value: regionCode.uppercased())) }
        if let pageToken, !pageToken.isEmpty { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps.queryItems = items
        let (data, response) = try await session.data(from: comps.url!)
        try validate(data: data, response: response)
        let detail = try JSONDecoder.youtube.decode(VideoResponse.self, from: data)
        return YouTubeSearchPage(videos: metrics(from: detail.items), nextPageToken: detail.nextPageToken)
    }

    public func channelSnapshot(reference: String) async throws -> ChannelSnapshot {
        try requireKey()
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        var items = [URLQueryItem(name: "part", value: "snippet,contentDetails,statistics"), URLQueryItem(name: "key", value: apiKey)]
        let parsed = ChannelReference(reference)
        items.append(URLQueryItem(name: parsed.parameter, value: parsed.value))
        comps.queryItems = items
        let (data, response) = try await session.data(from: comps.url!)
        try validate(data: data, response: response)
        let result = try JSONDecoder.youtube.decode(ChannelResponse.self, from: data)
        guard let channel = result.items.first else { throw YouTubeAPIError.channelNotFound }
        let uploads = channel.contentDetails.relatedPlaylists.uploads
        let recent = try await recentUploadMetrics(playlistID: uploads, maxResults: 30)
        let medViews = median(recent.map { Double($0.viewCount) }.filter { $0 > 0 })
        let medVPH = median(recent.map(\.viewsPerHour).filter { $0.isFinite && $0 > 0 })
        let topics = topicTerms(from: recent)
        return ChannelSnapshot(id: channel.id, title: channel.snippet.title, subscriberCount: Int(channel.statistics.subscriberCount ?? "0") ?? 0, medianViews: max(medViews, 1), medianViewsPerHour: max(medVPH, 1), recentTopics: topics)
    }

    private func recentUploadMetrics(playlistID: String, maxResults: Int) async throws -> [VideoMetric] {
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
        comps.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "playlistId", value: playlistID),
            URLQueryItem(name: "maxResults", value: String(clampResults(maxResults))),
            URLQueryItem(name: "key", value: apiKey)
        ]
        let (data, response) = try await session.data(from: comps.url!)
        try validate(data: data, response: response)
        let list = try JSONDecoder.youtube.decode(PlaylistItemsResponse.self, from: data)
        let ids = list.items.map(\.contentDetails.videoId)
        return ids.isEmpty ? [] : try await fetchDetails(ids: ids)
    }

    private func fetchDetails(ids: [String]) async throws -> [VideoMetric] {
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        comps.queryItems = [URLQueryItem(name: "part", value: "contentDetails,statistics,snippet"), URLQueryItem(name: "id", value: ids.joined(separator: ",")), URLQueryItem(name: "key", value: apiKey)]
        let (data, response) = try await session.data(from: comps.url!)
        try validate(data: data, response: response)
        let detail = try JSONDecoder.youtube.decode(VideoResponse.self, from: data)
        return metrics(from: detail.items)
    }

    private func metrics(from items: [VideoItem]) -> [VideoMetric] {
        items.compactMap { item in
            guard let snippet = item.snippet else { return nil }
            return VideoMetric(id: item.id, title: snippet.title.decodingHTMLEntities, channelID: snippet.channelId, channelTitle: snippet.channelTitle, publishedAt: snippet.publishedAt, durationSeconds: ISO8601Duration.seconds(item.contentDetails?.duration ?? "PT0S"), viewCount: Int(item.statistics?.viewCount ?? "0") ?? 0, likeCount: Int(item.statistics?.likeCount ?? ""), commentCount: Int(item.statistics?.commentCount ?? ""), thumbnailURL: snippet.thumbnails?.high?.url ?? snippet.thumbnails?.medium?.url, tags: snippet.tags ?? [])
        }
    }

    private func topicTerms(from videos: [VideoMetric]) -> [String] {
        let stop: Set<String> = ["der","die","das","und","oder","mit","für","von","ein","eine","auf","the","and","for","with","this","that","you","your","video","shorts"]
        var counts: [String: Int] = [:]
        for video in videos {
            let source = ([video.title] + video.tags).joined(separator: " ").lowercased()
            for token in source.components(separatedBy: CharacterSet.alphanumerics.inverted) where token.count >= 3 && !stop.contains(token) { counts[token, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(10).map(\.key)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 1 }
        let sorted = values.sorted(), mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private func requireKey() throws { if apiKey.isEmpty { throw YouTubeAPIError.missingAPIKey } }
    private func clampResults(_ value: Int) -> Int { min(max(value, 1), 50) }
    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw YouTubeAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) { throw YouTubeAPIError.api(apiError.error.message) }
            throw YouTubeAPIError.api("YouTube API Fehler \(http.statusCode)")
        }
    }
}

private struct ChannelReference {
    let parameter: String
    let value: String
    init(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "/channel/") {
            let tail = String(trimmed[range.upperBound...]).split(separator: "/").first.map(String.init) ?? trimmed
            parameter = "id"; value = tail
        } else if let at = trimmed.firstIndex(of: "@") {
            let tail = String(trimmed[at...]).split(separator: "/").first.map(String.init) ?? trimmed
            parameter = "forHandle"; value = tail
        } else if trimmed.hasPrefix("UC") {
            parameter = "id"; value = trimmed
        } else {
            parameter = "forHandle"; value = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        }
    }
}

private struct SearchResponse: Decodable { let nextPageToken: String?; let items: [SearchItem] }
private struct SearchItem: Decodable { let id: SearchID }
private struct SearchID: Decodable { let videoId: String }
private struct VideoResponse: Decodable { let nextPageToken: String?; let items: [VideoItem] }
private struct VideoItem: Decodable { let id: String; let snippet: VideoSnippet?; let contentDetails: ContentDetails?; let statistics: Statistics? }
private struct VideoSnippet: Decodable { let publishedAt: Date; let channelId: String; let title: String; let channelTitle: String; let thumbnails: ThumbnailSet?; let tags: [String]? }
private struct ThumbnailSet: Decodable { let medium: Thumbnail?; let high: Thumbnail? }
private struct Thumbnail: Decodable { let url: URL }
private struct ContentDetails: Decodable { let duration: String }
private struct Statistics: Decodable { let viewCount: String?; let likeCount: String?; let commentCount: String? }
private struct PlaylistItemsResponse: Decodable { let items: [PlaylistItem] }
private struct PlaylistItem: Decodable { let contentDetails: PlaylistItemDetails }
private struct PlaylistItemDetails: Decodable { let videoId: String }
private struct ChannelResponse: Decodable { let items: [ChannelItem] }
private struct ChannelItem: Decodable { let id: String; let snippet: ChannelSnippet; let contentDetails: ChannelContentDetails; let statistics: ChannelStatistics }
private struct ChannelSnippet: Decodable { let title: String }
private struct ChannelContentDetails: Decodable { let relatedPlaylists: RelatedPlaylists }
private struct RelatedPlaylists: Decodable { let uploads: String }
private struct ChannelStatistics: Decodable { let subscriberCount: String? }
private struct APIErrorEnvelope: Decodable { let error: APIErrorBody }
private struct APIErrorBody: Decodable { let message: String }

private extension JSONDecoder {
    static var youtube: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}

private enum ISO8601Duration {
    static func seconds(_ value: String) -> Int {
        var total = 0, number = "", inTime = false
        for ch in value {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber { number.append(ch); continue }
            guard inTime, let n = Int(number) else { number = ""; continue }
            if ch == "H" { total += n * 3600 } else if ch == "M" { total += n * 60 } else if ch == "S" { total += n }
            number = ""
        }
        return total
    }
}

private extension String {
    var decodingHTMLEntities: String { replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">") }
}
