import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class YouTubePublicClient {
    public init() {}

    public func resolveChannel(_ input: String, apiKey: String) async throws -> ConnectedChannel {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BlackstockError.missingAPIKey }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let directID = Self.extractChannelID(from: trimmed)
        let channelID: String
        if let directID {
            channelID = directID
        } else {
            let query = Self.extractHandleOrQuery(from: trimmed)
            let search: SearchResponse = try await get("search", items: [
                .init(name: "part", value: "snippet"), .init(name: "type", value: "channel"), .init(name: "maxResults", value: "5"), .init(name: "q", value: query), .init(name: "key", value: apiKey)
            ])
            guard let found = search.items.first?.snippet?.channelId ?? search.items.first?.id?.channelId else { throw BlackstockError.invalidChannel }
            channelID = found
        }
        let response: ChannelResponse = try await get("channels", items: [
            .init(name: "part", value: "snippet,statistics"), .init(name: "id", value: channelID), .init(name: "key", value: apiKey)
        ])
        guard let item = response.items.first else { throw BlackstockError.invalidChannel }
        let thumb = item.snippet.thumbnails?.high?.url ?? item.snippet.thumbnails?.default?.url
        return ConnectedChannel(youtubeChannelID: item.id, handle: item.snippet.customUrl, name: Self.clean(item.snippet.title), thumbnailURL: thumb.flatMap(URL.init(string:)), subscriberCount: Int(item.statistics?.subscriberCount ?? "0") ?? 0, videoCount: Int(item.statistics?.videoCount ?? "0") ?? 0)
    }

    public func recentVideos(channelID: String, apiKey: String, maxResults: Int = 30) async throws -> [PublicVideo] {
        let response: SearchResponse = try await get("search", items: [
            .init(name: "part", value: "snippet"), .init(name: "channelId", value: channelID), .init(name: "type", value: "video"), .init(name: "order", value: "date"), .init(name: "maxResults", value: String(min(maxResults, 50))), .init(name: "key", value: apiKey)
        ])
        return try await videoDetails(ids: response.items.compactMap { $0.id?.videoId }, apiKey: apiKey)
    }

    public func discover(query: String, apiKey: String, publishedAfter: Date, maxResults: Int = 35) async throws -> [PublicVideo] {
        let formatter = ISO8601DateFormatter()
        let response: SearchResponse = try await get("search", items: [
            .init(name: "part", value: "snippet"), .init(name: "type", value: "video"), .init(name: "order", value: "viewCount"), .init(name: "publishedAfter", value: formatter.string(from: publishedAfter)), .init(name: "maxResults", value: String(min(maxResults, 50))), .init(name: "q", value: query), .init(name: "key", value: apiKey)
        ])
        return try await videoDetails(ids: response.items.compactMap { $0.id?.videoId }, apiKey: apiKey)
    }

    public func timestampedCommentMoments(videoID: String, apiKey: String, duration: Double) async throws -> [ClipMoment] {
        let response: CommentThreadResponse = try await get("commentThreads", items: [
            .init(name: "part", value: "snippet"), .init(name: "videoId", value: videoID), .init(name: "order", value: "relevance"), .init(name: "textFormat", value: "plainText"), .init(name: "maxResults", value: "100"), .init(name: "key", value: apiKey)
        ])
        var counts: [Int: (count: Int, samples: [String])] = [:]
        for item in response.items {
            let text = item.snippet.topLevelComment.snippet.textDisplay
            for second in Self.extractTimestamps(from: text) where second >= 0 && Double(second) < duration {
                let bucket = max(0, (second / 5) * 5)
                var value = counts[bucket] ?? (0, [])
                value.count += 1
                if value.samples.count < 3 { value.samples.append(text) }
                counts[bucket] = value
            }
        }
        let maxCount = max(1, counts.values.map(\.count).max() ?? 1)
        return counts.map { second, value in
            let score = min(100, 55 + (Double(value.count) / Double(maxCount)) * 45)
            return ClipMoment(start: Double(second), end: min(duration, Double(second) + 35), score: score, title: "Publikums-Signal bei \(Self.timeText(Double(second)))", rationale: ["\(value.count) relevante Zeitmarken in Top-Kommentaren", "YouTube bleibt die Quelle; Blackstock lädt das Video nicht herunter."], previewText: value.samples.first ?? "Zeitmarke aus öffentlichen Kommentaren", source: "YouTube-Kommentare")
        }.sorted { $0.score > $1.score }.prefix(8).map { $0 }
    }

    private func videoDetails(ids: [String], apiKey: String) async throws -> [PublicVideo] {
        guard !ids.isEmpty else { return [] }
        let response: VideoResponse = try await get("videos", items: [
            .init(name: "part", value: "snippet,contentDetails,statistics"), .init(name: "id", value: ids.joined(separator: ",")), .init(name: "key", value: apiKey)
        ])
        let formatter = ISO8601DateFormatter()
        return response.items.compactMap { item in
            guard let published = formatter.date(from: item.snippet.publishedAt) else { return nil }
            let thumb = item.snippet.thumbnails?.maxres?.url ?? item.snippet.thumbnails?.high?.url ?? item.snippet.thumbnails?.medium?.url
            return PublicVideo(videoID: item.id, title: Self.clean(item.snippet.title), description: Self.clean(item.snippet.description), channelTitle: Self.clean(item.snippet.channelTitle), channelID: item.snippet.channelId, publishedAt: published, thumbnailURL: thumb.flatMap(URL.init(string:)), viewCount: Int(item.statistics?.viewCount ?? "0") ?? 0, likeCount: Int(item.statistics?.likeCount ?? "0") ?? 0, commentCount: Int(item.statistics?.commentCount ?? "0") ?? 0, durationSeconds: Self.parseDuration(item.contentDetails.duration), categoryID: item.snippet.categoryId)
        }
    }

    private func get<T: Decodable>(_ path: String, items: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(path)")!
        components.queryItems = items
        guard let url = components.url else { throw BlackstockError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw BlackstockError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public static func parseDuration(_ value: String) -> Double {
        let pattern = #"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return 0 }
        func number(_ index: Int) -> Double {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swift = Range(range, in: value) else { return 0 }
            return Double(value[swift]) ?? 0
        }
        return number(1) * 86400 + number(2) * 3600 + number(3) * 60 + number(4)
    }

    public static func extractTimestamps(from text: String) -> [Int] {
        let pattern = #"(?<!\d)(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            func int(_ index: Int) -> Int { let r = match.range(at: index); return r.location == NSNotFound ? 0 : Int(ns.substring(with: r)) ?? 0 }
            let h = int(1), m = int(2), s = int(3)
            guard m < 60, s < 60 else { return nil }
            return h * 3600 + m * 60 + s
        }
    }

    public static func extractChannelID(from input: String) -> String? {
        if input.hasPrefix("UC"), input.count >= 20 { return input }
        if let range = input.range(of: "/channel/") { return input[range.upperBound...].split(separator: "/").first.map(String.init) }
        return nil
    }

    private static func extractHandleOrQuery(from input: String) -> String {
        if let at = input.lastIndex(of: "@") { return String(input[at...]).split(separator: "/").first.map(String.init) ?? input }
        return input.replacingOccurrences(of: "https://www.youtube.com/", with: "").replacingOccurrences(of: "https://youtube.com/", with: "")
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func timeText(_ seconds: Double) -> String { let value = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", value / 60, value % 60) }
}

public enum ChannelDNAService {
    private static let stopwords: Set<String> = ["the","and","for","with","this","that","from","your","you","are","was","have","has","how","why","what","when","into","about","new","video","official","der","die","das","und","für","mit","von","eine","einer","einen","ein","ist","sind","war","wie","was","warum","wenn","neue","neu","video","ich","du","wir","im","in","auf","zu","den","dem"]

    public static func build(from videos: [PublicVideo]) -> ChannelDNA {
        guard !videos.isEmpty else { return ChannelDNA() }
        var counts: [String: Int] = [:], germanSignals = 0, englishSignals = 0
        for video in videos {
            let text = video.title + " " + video.description.prefix(240)
            for token in tokens(text) { counts[token, default: 0] += token.count >= 7 ? 2 : 1 }
            let lower = " " + text.lowercased() + " "
            germanSignals += [" der "," die "," das "," und "," nicht "," für "].filter { lower.contains($0) }.count
            englishSignals += [" the "," and "," this "," not "," for "," with "].filter { lower.contains($0) }.count
        }
        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        let keywords = Array(ranked.prefix(14)), pillars = Array(ranked.prefix(5))
        return ChannelDNA(primaryTopic: pillars.first?.capitalized ?? "Allgemein", contentPillars: pillars.map { $0.capitalized }, keywords: keywords, languageHint: germanSignals >= englishSignals ? "Deutsch" : "Englisch", sampleSize: videos.count, updatedAt: .now)
    }

    public static func fit(video: PublicVideo, dna: ChannelDNA) -> Double {
        guard !dna.keywords.isEmpty else { return 50 }
        let haystack = Set(tokens(video.title + " " + video.description.prefix(400))), keywordSet = Set(dna.keywords)
        let hits = haystack.intersection(keywordSet).count, titleHits = Set(tokens(video.title)).intersection(keywordSet).count
        return min(100, max(0, Double(hits) / Double(max(4, keywordSet.count)) * 70 + Double(titleHits) * 9))
    }

    private static func tokens(_ value: String) -> [String] { value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 && !stopwords.contains($0) && Int($0) == nil } }
}

public enum OpportunityEngine {
    public static func rank(videos: [PublicVideo], dna: ChannelDNA, now: Date = .now) -> [Opportunity] {
        guard !videos.isEmpty else { return [] }
        let velocities = videos.map { velocity(video: $0, now: now) }, maxVelocity = max(1, velocities.max() ?? 1)
        return zip(videos, velocities).map { video, velocity in
            let ageHours = max(1, now.timeIntervalSince(video.publishedAt) / 3600), freshness = max(0, min(100, 100 - ageHours / 168 * 100)), momentum = min(100, velocity / maxVelocity * 100), fit = ChannelDNAService.fit(video: video, dna: dna), score = fit * 0.52 + momentum * 0.33 + freshness * 0.15
            var reasons: [String] = []
            if fit >= 70 { reasons.append("Starker Fit zur Channel-DNA") } else if fit >= 45 { reasons.append("Plausibler Themen-Fit") }
            if momentum >= 70 { reasons.append("Hohe aktuelle View-Geschwindigkeit") }
            if freshness >= 75 { reasons.append("Sehr frisch veröffentlicht") }
            if reasons.isEmpty { reasons.append("Wird beobachtet, aber nicht priorisiert") }
            return Opportunity(video: video, channelFit: fit, momentum: momentum, freshness: freshness, score: score, reasons: reasons, access: .youtubeNative)
        }.sorted { $0.score > $1.score }
    }
    private static func velocity(video: PublicVideo, now: Date) -> Double { Double(video.viewCount) / max(1, now.timeIntervalSince(video.publishedAt) / 3600) }
}

private struct SearchResponse: Decodable { let items: [SearchItem] }
private struct SearchItem: Decodable { let id: SearchID?; let snippet: SearchSnippet? }
private struct SearchID: Decodable { let videoId: String?; let channelId: String? }
private struct SearchSnippet: Decodable { let channelId: String? }
private struct ChannelResponse: Decodable { let items: [ChannelItem] }
private struct ChannelItem: Decodable { let id: String; let snippet: ChannelSnippet; let statistics: ChannelStatistics? }
private struct ChannelSnippet: Decodable { let title: String; let customUrl: String?; let thumbnails: ThumbnailSet? }
private struct ChannelStatistics: Decodable { let subscriberCount: String?; let videoCount: String? }
private struct VideoResponse: Decodable { let items: [VideoItem] }
private struct VideoItem: Decodable { let id: String; let snippet: VideoSnippet; let contentDetails: ContentDetails; let statistics: VideoStatistics? }
private struct VideoSnippet: Decodable { let publishedAt: String; let channelId: String; let title: String; let description: String; let thumbnails: ThumbnailSet?; let channelTitle: String; let categoryId: String }
private struct ContentDetails: Decodable { let duration: String }
private struct VideoStatistics: Decodable { let viewCount: String?; let likeCount: String?; let commentCount: String? }
private struct ThumbnailSet: Decodable { let `default`: Thumbnail?; let medium: Thumbnail?; let high: Thumbnail?; let maxres: Thumbnail? }
private struct Thumbnail: Decodable { let url: String }
private struct CommentThreadResponse: Decodable { let items: [CommentThreadItem] }
private struct CommentThreadItem: Decodable { let snippet: CommentThreadSnippet }
private struct CommentThreadSnippet: Decodable { let topLevelComment: Comment }
private struct Comment: Decodable { let snippet: CommentSnippet }
private struct CommentSnippet: Decodable { let textDisplay: String }
