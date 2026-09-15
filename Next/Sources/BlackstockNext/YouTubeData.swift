import Foundation

struct YouTubeChannelSnapshot: Hashable {
    let identity: ChannelIdentity
    let uploadsPlaylistID: String
    let subscriberCount: Int
    let viewCount: Int
    let videoCount: Int
}

struct YouTubePlaylist: Identifiable, Hashable { let id: String; let title: String }

struct AnalyticsSummary: Hashable {
    let views: Int
    let estimatedMinutesWatched: Double
    let averageViewDuration: Double
    let subscribersGained: Int
}

final class YouTubeDataService {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func myChannel(accessToken: String) async throws -> YouTubeChannelSnapshot {
        let root = try await object("https://www.googleapis.com/youtube/v3/channels?part=snippet,contentDetails,statistics&mine=true", token: accessToken)
        guard let item = (root["items"] as? [[String: Any]])?.first,
              let id = item["id"] as? String,
              let snippet = item["snippet"] as? [String: Any],
              let related = ((item["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any]),
              let uploads = related["uploads"] as? String else { throw YouTubeUploadError(message: "Für dieses Google-Konto wurde kein YouTube-Kanal gefunden.") }
        let stats = item["statistics"] as? [String: Any] ?? [:]
        let identity = ChannelIdentity(id: id, name: snippet["title"] as? String ?? "YouTube-Kanal", description: snippet["description"] as? String ?? "", primaryTopic: "", language: snippet["defaultLanguage"] as? String ?? "de")
        return .init(identity: identity, uploadsPlaylistID: uploads, subscriberCount: Int(stats["subscriberCount"] as? String ?? "") ?? 0, viewCount: Int(stats["viewCount"] as? String ?? "") ?? 0, videoCount: Int(stats["videoCount"] as? String ?? "") ?? 0)
    }

    func channelVideos(uploadsPlaylistID: String, accessToken: String, maximum: Int = 80) async throws -> [ChannelVideoProfile] {
        var ids: [String] = []; var pageToken: String?
        while ids.count < maximum {
            var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
            c.queryItems = [.init(name: "part", value: "contentDetails"), .init(name: "playlistId", value: uploadsPlaylistID), .init(name: "maxResults", value: String(min(50, maximum - ids.count)))]
            if let pageToken { c.queryItems?.append(.init(name: "pageToken", value: pageToken)) }
            let root = try await object(c.url!.absoluteString, token: accessToken)
            for item in root["items"] as? [[String: Any]] ?? [] { if let id = (item["contentDetails"] as? [String: Any])?["videoId"] as? String { ids.append(id) } }
            pageToken = root["nextPageToken"] as? String
            if pageToken == nil { break }
        }
        return try await profiles(ids: ids, token: accessToken)
    }

    func popular(regionCode: String, dna: ChannelDNA, accessToken: String) async throws -> [Opportunity] {
        var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        c.queryItems = [.init(name: "part", value: "snippet,statistics,contentDetails"), .init(name: "chart", value: "mostPopular"), .init(name: "regionCode", value: regionCode), .init(name: "maxResults", value: "50")]
        let root = try await object(c.url!.absoluteString, token: accessToken)
        let dnaEngine = ChannelDNAEngine()
        return (root["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let snippet = item["snippet"] as? [String: Any], let title = snippet["title"] as? String else { return nil }
            let description = snippet["description"] as? String ?? ""
            let text = ([title, description] + (snippet["tags"] as? [String] ?? [])).joined(separator: " ")
            let stats = item["statistics"] as? [String: Any] ?? [:]
            let views = Int(stats["viewCount"] as? String ?? "") ?? 0
            let published = Self.date(snippet["publishedAt"] as? String) ?? Date()
            let ageHours = max(1, Date().timeIntervalSince(published) / 3600)
            let momentum = min(1, log10(max(10, Double(views) / ageHours)) / 5)
            return Opportunity(id: id, videoID: id, channelTitle: snippet["channelTitle"] as? String ?? "", title: title, description: description, publishedAt: published, viewCount: views, durationSeconds: Self.duration((item["contentDetails"] as? [String: Any])?["duration"] as? String ?? "PT0S"), relevance: dnaEngine.relevance(of: text, to: dna), momentum: momentum)
        }.sorted { $0.score > $1.score }
    }

    func playlists(accessToken: String) async throws -> [YouTubePlaylist] {
        let root = try await object("https://www.googleapis.com/youtube/v3/playlists?part=snippet&mine=true&maxResults=50", token: accessToken)
        return (root["items"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String, let title = (item["snippet"] as? [String: Any])?["title"] as? String else { return nil }
            return .init(id: id, title: title)
        }
    }

    func add(videoID: String, toPlaylist playlistID: String, accessToken: String) async throws {
        var r = URLRequest(url: URL(string: "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet")!); r.httpMethod = "POST"
        r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["snippet": ["playlistId": playlistID, "resourceId": ["kind": "youtube#video", "videoId": videoID]]])
        let (data, response) = try await session.data(for: r); try GoogleOAuthService.requireSuccess(response, data: data)
    }

    private func profiles(ids: [String], token: String) async throws -> [ChannelVideoProfile] {
        var out: [ChannelVideoProfile] = []
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = Array(ids[start..<min(ids.count, start + 50)])
            var c = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
            c.queryItems = [.init(name: "part", value: "snippet,statistics,contentDetails"), .init(name: "id", value: batch.joined(separator: ","))]
            let root = try await object(c.url!.absoluteString, token: token)
            for item in root["items"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String, let s = item["snippet"] as? [String: Any] else { continue }
                let stats = item["statistics"] as? [String: Any] ?? [:]
                out.append(.init(id: id, title: s["title"] as? String ?? "", description: s["description"] as? String ?? "", publishedAt: Self.date(s["publishedAt"] as? String) ?? Date(), viewCount: Int(stats["viewCount"] as? String ?? "") ?? 0, likeCount: Int(stats["likeCount"] as? String ?? "") ?? 0, commentCount: Int(stats["commentCount"] as? String ?? "") ?? 0, durationSeconds: Self.duration((item["contentDetails"] as? [String: Any])?["duration"] as? String ?? "PT0S"), tags: s["tags"] as? [String] ?? []))
            }
        }
        return out.sorted { $0.publishedAt > $1.publishedAt }
    }

    private func object(_ address: String, token: String) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: address)!); r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: r); try GoogleOAuthService.requireSuccess(response, data: data)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func date(_ value: String?) -> Date? { guard let value else { return nil }; return ISO8601DateFormatter().date(from: value) }
    private static func duration(_ value: String) -> Double {
        let regex = try? NSRegularExpression(pattern: #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?"#)
        guard let m = regex?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return 0 }
        func g(_ i: Int) -> Double { let r = m.range(at: i); guard r.location != NSNotFound, let rr = Range(r, in: value) else { return 0 }; return Double(value[rr]) ?? 0 }
        return g(1) * 3600 + g(2) * 60 + g(3)
    }
}

final class YouTubeAnalyticsService {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func summary(days: Int = 28, accessToken: String) async throws -> AnalyticsSummary {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        let end = Date(); let start = Calendar.current.date(byAdding: .day, value: -max(1, days), to: end) ?? end
        var c = URLComponents(string: "https://youtubeanalytics.googleapis.com/v2/reports")!
        c.queryItems = [.init(name: "ids", value: "channel==MINE"), .init(name: "startDate", value: formatter.string(from: start)), .init(name: "endDate", value: formatter.string(from: end)), .init(name: "metrics", value: "views,estimatedMinutesWatched,averageViewDuration,subscribersGained")]
        var r = URLRequest(url: c.url!); r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: r); try GoogleOAuthService.requireSuccess(response, data: data)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let row = (root["rows"] as? [[Any]])?.first ?? []
        return .init(views: (row.indices.contains(0) ? row[0] as? NSNumber : nil)?.intValue ?? 0, estimatedMinutesWatched: (row.indices.contains(1) ? row[1] as? NSNumber : nil)?.doubleValue ?? 0, averageViewDuration: (row.indices.contains(2) ? row[2] as? NSNumber : nil)?.doubleValue ?? 0, subscribersGained: (row.indices.contains(3) ? row[3] as? NSNumber : nil)?.intValue ?? 0)
    }
}
