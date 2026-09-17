#if os(macOS)
import Foundation
import BlackstockCore

enum YouTubeAnalyticsServiceError: LocalizedError {
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "YouTube Analytics hat eine unerwartete Antwort geliefert."
        case .api(let message): return message
        }
    }
}

struct YouTubeAnalyticsService: Sendable {
    func load(channelID: String, days: Int = 28) async throws -> AnalyticsDataset {
        let token = try await GoogleYouTubeAuth.freshAccessToken(channelID: channelID)
        let calendar = Calendar(identifier: .gregorian)
        let end = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let start = calendar.date(byAdding: .day, value: -max(days, 1), to: end) ?? end
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "https://youtubeanalytics.googleapis.com/v2/reports")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: "channel==MINE"),
            URLQueryItem(name: "startDate", value: formatter.string(from: start)),
            URLQueryItem(name: "endDate", value: formatter.string(from: end)),
            URLQueryItem(name: "metrics", value: "views,estimatedMinutesWatched"),
            URLQueryItem(name: "dimensions", value: "video"),
            URLQueryItem(name: "sort", value: "-views"),
            URLQueryItem(name: "maxResults", value: "100")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw YouTubeAnalyticsServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw YouTubeAnalyticsServiceError.api(Self.apiMessage(data) ?? "YouTube Analytics konnte nicht geladen werden.")
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let headers = object["columnHeaders"] as? [[String: Any]] else {
            throw YouTubeAnalyticsServiceError.invalidResponse
        }
        let names = headers.compactMap { $0["name"] as? String }
        guard let videoIndex = names.firstIndex(of: "video"),
              let viewsIndex = names.firstIndex(of: "views"),
              let watchIndex = names.firstIndex(of: "estimatedMinutesWatched") else {
            throw YouTubeAnalyticsServiceError.invalidResponse
        }
        let rawRows = object["rows"] as? [[Any]] ?? []
        let videoIDs = rawRows.compactMap { row -> String? in
            guard row.indices.contains(videoIndex) else { return nil }
            return row[videoIndex] as? String
        }
        let titles = try await videoTitles(ids: videoIDs, accessToken: token)
        let rows = rawRows.compactMap { row -> AnalyticsRow? in
            guard row.indices.contains(videoIndex), row.indices.contains(viewsIndex), row.indices.contains(watchIndex),
                  let videoID = row[videoIndex] as? String else { return nil }
            let views = Self.intValue(row[viewsIndex])
            let watchMinutes = Self.doubleValue(row[watchIndex])
            return AnalyticsRow(
                title: titles[videoID] ?? "YouTube Video · \(videoID)",
                views: views,
                watchTimeHours: watchMinutes / 60,
                impressions: 0,
                clickThroughRate: nil
            )
        }
        return AnalyticsDataset(rows: rows)
    }

    private func videoTitles(ids: [String], accessToken: String) async throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < ids.count {
            let end = min(index + 50, ids.count)
            let chunk = Array(ids[index..<end])
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "id", value: chunk.joined(separator: ",")),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let payload = try? JSONDecoder().decode(VideoTitleResponse.self, from: data) {
                for item in payload.items { result[item.id] = item.snippet.title }
            }
            index = end
        }
        return result
    }

    private static func intValue(_ value: Any) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(Double(string) ?? 0) }
        return 0
    }

    private static func doubleValue(_ value: Any) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private static func apiMessage(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}

private struct VideoTitleResponse: Decodable {
    let items: [VideoTitleItem]
}
private struct VideoTitleItem: Decodable {
    let id: String
    let snippet: VideoTitleSnippet
}
private struct VideoTitleSnippet: Decodable {
    let title: String
}
#endif
