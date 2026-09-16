import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct YouTubeSearchPage: Sendable {
    public let videos: [VideoMetric]
    public let nextPageToken: String?
    public init(videos: [VideoMetric], nextPageToken: String?) { self.videos = videos; self.nextPageToken = nextPageToken }
}
public protocol YouTubeSearching: Sendable { func search(query: String, pageToken: String?, maxResults: Int) async throws -> YouTubeSearchPage }
public enum YouTubeAPIError: LocalizedError {
    case missingAPIKey, invalidResponse, api(String)
    public var errorDescription: String? {
        switch self { case .missingAPIKey: return "Für Live-Trends fehlt ein YouTube Data API Key."; case .invalidResponse: return "YouTube hat eine unerwartete Antwort geliefert."; case .api(let message): return message }
    }
}
public struct YouTubeDataAPIClient: YouTubeSearching {
    private let apiKey: String
    private let session: URLSession
    public init(apiKey: String, session: URLSession = .shared) { self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines); self.session = session }
    public func search(query: String, pageToken: String? = nil, maxResults: Int = 25) async throws -> YouTubeSearchPage {
        guard !apiKey.isEmpty else { throw YouTubeAPIError.missingAPIKey }
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        var items = [URLQueryItem(name: "part", value: "snippet"), URLQueryItem(name: "type", value: "video"), URLQueryItem(name: "order", value: "viewCount"), URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: String(min(max(maxResults, 1), 50))), URLQueryItem(name: "publishedAfter", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-14 * 86400))), URLQueryItem(name: "key", value: apiKey)]
        if let pageToken, !pageToken.isEmpty { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps.queryItems = items
        let (data, response) = try await session.data(from: comps.url!); try validate(data: data, response: response)
        let search = try JSONDecoder.youtube.decode(SearchResponse.self, from: data)
        let ids = search.items.map(\.id.videoId).filter { !$0.isEmpty }
        guard !ids.isEmpty else { return YouTubeSearchPage(videos: [], nextPageToken: search.nextPageToken) }
        return YouTubeSearchPage(videos: try await fetchDetails(ids: ids), nextPageToken: search.nextPageToken)
    }
    private func fetchDetails(ids: [String]) async throws -> [VideoMetric] {
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        comps.queryItems = [URLQueryItem(name: "part", value: "contentDetails,statistics,snippet"), URLQueryItem(name: "id", value: ids.joined(separator: ",")), URLQueryItem(name: "key", value: apiKey)]
        let (data, response) = try await session.data(from: comps.url!); try validate(data: data, response: response)
        let detail = try JSONDecoder.youtube.decode(VideoResponse.self, from: data)
        return detail.items.compactMap { item in
            guard let snippet = item.snippet else { return nil }
            return VideoMetric(id: item.id, title: snippet.title.decodingHTMLEntities, channelID: snippet.channelId, channelTitle: snippet.channelTitle, publishedAt: snippet.publishedAt, durationSeconds: ISO8601Duration.seconds(item.contentDetails?.duration ?? "PT0S"), viewCount: Int(item.statistics?.viewCount ?? "0") ?? 0, likeCount: Int(item.statistics?.likeCount ?? ""), commentCount: Int(item.statistics?.commentCount ?? ""), thumbnailURL: snippet.thumbnails?.high?.url ?? snippet.thumbnails?.medium?.url, tags: snippet.tags ?? [])
        }
    }
    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw YouTubeAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) { throw YouTubeAPIError.api(apiError.error.message) }
            throw YouTubeAPIError.api("YouTube API Fehler \(http.statusCode)")
        }
    }
}
private struct SearchResponse: Decodable { let nextPageToken: String?; let items: [SearchItem] }
private struct SearchItem: Decodable { let id: SearchID }
private struct SearchID: Decodable { let videoId: String }
private struct VideoResponse: Decodable { let items: [VideoItem] }
private struct VideoItem: Decodable { let id: String; let snippet: VideoSnippet?; let contentDetails: ContentDetails?; let statistics: Statistics? }
private struct VideoSnippet: Decodable { let publishedAt: Date; let channelId: String; let title: String; let channelTitle: String; let thumbnails: ThumbnailSet?; let tags: [String]? }
private struct ThumbnailSet: Decodable { let medium: Thumbnail?; let high: Thumbnail? }
private struct Thumbnail: Decodable { let url: URL }
private struct ContentDetails: Decodable { let duration: String }
private struct Statistics: Decodable { let viewCount: String?; let likeCount: String?; let commentCount: String? }
private struct APIErrorEnvelope: Decodable { let error: APIErrorBody }
private struct APIErrorBody: Decodable { let message: String }
private extension JSONDecoder { static var youtube: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
private enum ISO8601Duration {
    static func seconds(_ value: String) -> Int {
        var total = 0, number = ""; var inTime = false
        for ch in value { if ch == "T" { inTime = true; continue }; if ch.isNumber { number.append(ch); continue }; guard inTime, let n = Int(number) else { number = ""; continue }; if ch == "H" { total += n * 3600 } else if ch == "M" { total += n * 60 } else if ch == "S" { total += n }; number = "" }
        return total
    }
}
private extension String { var decodingHTMLEntities: String { replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">") } }
