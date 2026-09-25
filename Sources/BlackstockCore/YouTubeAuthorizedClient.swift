import Foundation

public struct YouTubeChannelIdentity: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let handle: String?
    public let avatarURL: URL?
    public let subscriberCount: Int?
    public let uploadsPlaylistID: String?
    public let viewCount: Int?
    public let videoCount: Int?

    public init(
        id: String,
        title: String,
        handle: String?,
        avatarURL: URL?,
        subscriberCount: Int?,
        uploadsPlaylistID: String?,
        viewCount: Int? = nil,
        videoCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.handle = handle
        self.avatarURL = avatarURL
        self.subscriberCount = subscriberCount
        self.uploadsPlaylistID = uploadsPlaylistID
        self.viewCount = viewCount
        self.videoCount = videoCount
    }
}

public struct YouTubeOpportunityMetrics: Codable, Sendable, Equatable {
    public let viewCount: Int?
    public let likeCount: Int?
    public let commentCount: Int?
    public let publishedAt: Date?
    public let retrievedAt: Date

    public init(
        viewCount: Int?,
        likeCount: Int?,
        commentCount: Int?,
        publishedAt: Date?,
        retrievedAt: Date
    ) {
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.publishedAt = publishedAt
        self.retrievedAt = retrievedAt
    }

    public var missingSignals: [String] {
        var missing: [String] = []
        if viewCount == nil { missing.append("Views") }
        if likeCount == nil { missing.append("Likes") }
        if commentCount == nil { missing.append("Kommentare") }
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
    public let contentKind: YouTubeOpportunityContentKind
    public let durationSeconds: Int?
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
        contentKind: YouTubeOpportunityContentKind = .video,
        durationSeconds: Int? = nil,
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
        self.contentKind = contentKind
        self.durationSeconds = durationSeconds
        self.metrics = metrics
    }
}

public enum OpportunityContentFilter: String, Codable, Sendable, CaseIterable, Hashable {
    case all
    case shorts
    case videos
    case live

    public var germanTitle: String {
        switch self {
        case .all: return "Alle"
        case .shorts: return "Shorts"
        case .videos: return "Videos"
        case .live: return "Live"
        }
    }
}

public enum YouTubeOpportunityContentKind: String, Codable, Sendable, Equatable {
    case short
    case video
    case live

    public var germanTitle: String {
        switch self {
        case .short: return "Shorts-Kandidat"
        case .video: return "Video"
        case .live: return "Live"
        }
    }
}

public enum OpportunitySortMode: String, Codable, Sendable, CaseIterable, Hashable {
    case relevance
    case newest
    case views

    public var youtubeOrderParameter: String {
        switch self {
        case .relevance: return "relevance"
        case .newest: return "date"
        case .views: return "viewCount"
        }
    }

    public var germanTitle: String {
        switch self {
        case .relevance: return "YouTube-Relevanz"
        case .newest: return "Neueste"
        case .views: return "Views"
        }
    }

    public var germanExplanation: String {
        switch self {
        case .relevance:
            return "Die Reihenfolge kommt direkt aus YouTubes Relevanzsortierung für die Suchanfrage."
        case .newest:
            return "Die Reihenfolge kommt direkt aus YouTubes Datums-Sortierung."
        case .views:
            return "Die Reihenfolge kommt direkt aus YouTubes View-Count-Sortierung."
        }
    }
}

public enum OpportunityTimeWindow: String, Codable, Sendable, CaseIterable, Hashable {
    case last6Hours
    case last12Hours
    case last24Hours
    case last3Days
    case last7Days
    case last30Days
    case allTime

    public var germanTitle: String {
        switch self {
        case .last6Hours: return "6 Std."
        case .last12Hours: return "12 Std."
        case .last24Hours: return "24 Std."
        case .last3Days: return "3 Tage"
        case .last7Days: return "7 Tage"
        case .last30Days: return "30 Tage"
        case .allTime: return "Gesamt"
        }
    }

    public func publishedAfter(now: Date) -> Date? {
        let seconds: TimeInterval
        switch self {
        case .last6Hours:
            seconds = 6 * 60 * 60
        case .last12Hours:
            seconds = 12 * 60 * 60
        case .last24Hours:
            seconds = 24 * 60 * 60
        case .last3Days:
            seconds = 3 * 24 * 60 * 60
        case .last7Days:
            seconds = 7 * 24 * 60 * 60
        case .last30Days:
            seconds = 30 * 24 * 60 * 60
        case .allTime:
            return nil
        }
        return now.addingTimeInterval(-seconds)
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
                subscriberCount: $0.statistics.flatMap {
                    Int($0.subscriberCount ?? "")
                },
                uploadsPlaylistID:
                    $0.contentDetails?.relatedPlaylists.uploads,
                viewCount: $0.statistics.flatMap {
                    Int($0.viewCount ?? "")
                },
                videoCount: $0.statistics.flatMap {
                    Int($0.videoCount ?? "")
                }
            )
        }
    }

    public static func sortedOpportunities(_ candidates: [YouTubeOpportunityCandidate], order: OpportunitySortMode) -> [YouTubeOpportunityCandidate] {
        guard order != .relevance else { return candidates }
        return candidates.enumerated().sorted { lhs, rhs in
            if order == .views {
                let a = lhs.element.metrics.viewCount ?? -1
                let b = rhs.element.metrics.viewCount ?? -1
                return a == b ? lhs.offset < rhs.offset : a > b
            }
            return lhs.element.publishedAt == rhs.element.publishedAt
                ? lhs.offset < rhs.offset : (lhs.element.publishedAt ?? .distantPast) > (rhs.element.publishedAt ?? .distantPast)
        }.map(\.element)
    }

    public func firstOpportunityCandidates(
        query: String,
        categoryID: String? = nil,
        regionCode: String? = nil,
        relevanceLanguage: String? = nil,
        publishedAfter: Date? = nil,
        maxResults: Int = 12,
        order: OpportunitySortMode = .relevance,
        contentFilter: OpportunityContentFilter = .all,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> [YouTubeOpportunityCandidate] {
        try await opportunityPage(query: query, categoryID: categoryID,
            regionCode: regionCode, relevanceLanguage: relevanceLanguage,
            publishedAfter: publishedAfter, maxResults: maxResults, order: order,
            contentFilter: contentFilter, session: session, now: now).candidates
    }

    public func opportunityPage(
        query: String,
        categoryID: String? = nil,
        regionCode: String? = nil,
        relevanceLanguage: String? = nil,
        publishedAfter: Date? = nil,
        maxResults: Int = 12,
        order: OpportunitySortMode = .relevance,
        contentFilter: OpportunityContentFilter = .all,
        pageToken: String? = nil,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> YouTubeOpportunityPage {
        var search = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/search"
        )!
        var queryItems: [URLQueryItem] = [
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(
                name: "maxResults",
                value: String(min(max(maxResults, 1), 50))
            ),
            .init(
                name: "order",
                value: order.youtubeOrderParameter
            ),
            .init(
                name: "videoEmbeddable",
                value: "true"
            ),
            .init(
                name: "videoSyndicated",
                value: "true"
            )
        ]
        if contentFilter == .live {
            queryItems.append(
                .init(name: "eventType", value: "live")
            )
        }

        let trimmedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedQuery.isEmpty {
            queryItems.append(
                .init(name: "q", value: trimmedQuery)
            )
        }
        if let categoryID,
           !categoryID.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            queryItems.append(
                .init(name: "videoCategoryId", value: categoryID)
            )
        }
        if let regionCode,
           !regionCode.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            queryItems.append(
                .init(name: "regionCode", value: regionCode)
            )
        }
        if let relevanceLanguage,
           !relevanceLanguage.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            queryItems.append(
                .init(
                    name: "relevanceLanguage",
                    value: relevanceLanguage
                )
            )
        }
        if let publishedAfter {
            queryItems.append(
                .init(
                    name: "publishedAfter",
                    value: ISO8601DateFormatter()
                        .string(from: publishedAfter)
                )
            )
        }
        if let pageToken { queryItems.append(.init(name: "pageToken", value: pageToken)) }
        search.queryItems = queryItems

        let searchData = try await perform(
            search.url!,
            session: session
        )
        let searchResponse = try JSONDecoder.youtube.decode(
            SearchListResponse.self,
            from: searchData
        )
        let searchItems = searchResponse.items.compactMap {
            item -> SearchItem? in
            item.id.videoId == nil ? nil : item
        }

        let videoIDs = searchItems.compactMap(\.id.videoId)
        let videos = try await loadVideoDetails(
            ids: videoIDs,
            session: session
        )

        let candidates: [YouTubeOpportunityCandidate] = searchItems.compactMap { item in
            guard let videoID = item.id.videoId else {
                return nil
            }
            let video = videos[videoID]
            let durationSeconds = Self.durationSeconds(
                from: video?.contentDetails?.duration
            )
            let contentKind = Self.contentKind(
                video: video,
                durationSeconds: durationSeconds
            )
            let matchesFilter: Bool
            switch contentFilter {
            case .all:
                matchesFilter = true
            case .shorts:
                matchesFilter = contentKind == .short
            case .videos:
                matchesFilter = contentKind == .video
            case .live:
                matchesFilter = contentKind == .live
            }
            guard matchesFilter else {
                return nil
            }

            let metrics = YouTubeOpportunityMetrics(
                viewCount: video?.statistics.flatMap {
                    Int($0.viewCount ?? "")
                },
                likeCount: video?.statistics.flatMap {
                    Int($0.likeCount ?? "")
                },
                commentCount: video?.statistics.flatMap {
                    Int($0.commentCount ?? "")
                },
                publishedAt: item.snippet.publishedAt,
                retrievedAt: now
            )

            return YouTubeOpportunityCandidate(
                videoID: videoID,
                title: Self.decodedYouTubeText(item.snippet.title),
                channelID: item.snippet.channelId,
                channelTitle: Self.decodedYouTubeText(item.snippet.channelTitle),
                publishedAt: item.snippet.publishedAt,
                thumbnailURL:
                    item.snippet.thumbnails?.medium?.url
                    ?? item.snippet.thumbnails?.defaultImage?.url,
                query: trimmedQuery.isEmpty
                    ? "category:\(categoryID ?? "all")"
                    : trimmedQuery,
                retrievedAt: now,
                embeddable: video?.status?.embeddable,
                contentKind: contentKind,
                durationSeconds: durationSeconds,
                metrics: metrics
            )
        }
        return YouTubeOpportunityPage(candidates: Self.sortedOpportunities(candidates, order: order),
            nextPageToken: searchResponse.nextPageToken)
    }

    public func categoryOpportunityCandidates(
        categoryID: String,
        categoryTitle: String,
        regionCode: String,
        relevanceLanguage: String? = nil,
        timeWindow: OpportunityTimeWindow = .allTime,
        maxResults: Int = 12,
        order: OpportunitySortMode = .relevance,
        contentFilter: OpportunityContentFilter = .all,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> [YouTubeOpportunityCandidate] {
        let trimmedCategoryID = categoryID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedCategoryTitle = categoryTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let trimmedRegion = regionCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedCategoryID.isEmpty,
              !trimmedRegion.isEmpty else {
            return []
        }

        if timeWindow == .allTime,
           contentFilter != .live,
           contentFilter != .shorts,
           order == .relevance {
            let popular = try await mostPopularOpportunityCandidates(
                categoryID: trimmedCategoryID,
                regionCode: trimmedRegion,
                maxResults: maxResults,
                session: session,
                now: now
            )
            let filteredPopular = popular.filter {
                switch contentFilter {
                case .all:
                    return true
                case .videos:
                    return $0.contentKind == .video
                case .shorts:
                    return $0.contentKind == .short
                case .live:
                    return $0.contentKind == .live
                }
            }
            if !filteredPopular.isEmpty {
                return filteredPopular
            }
        }

        let boundedOrder = order
        let publishedAfter =
            timeWindow.publishedAfter(now: now)

        let categoryOnly =
            try await firstOpportunityCandidates(
                query: "",
                categoryID: trimmedCategoryID,
                regionCode: trimmedRegion,
                relevanceLanguage: relevanceLanguage,
                publishedAfter: publishedAfter,
                maxResults: maxResults,
                order: boundedOrder,
                contentFilter: contentFilter,
                session: session,
                now: now
            )
        if !categoryOnly.isEmpty {
            return categoryOnly
        }

        guard !trimmedCategoryTitle.isEmpty else {
            return []
        }
        return try await firstOpportunityCandidates(
            query: trimmedCategoryTitle,
            categoryID: trimmedCategoryID,
            regionCode: trimmedRegion,
            relevanceLanguage: relevanceLanguage,
            publishedAfter: publishedAfter,
            maxResults: maxResults,
            order: boundedOrder,
            contentFilter: contentFilter,
            session: session,
            now: now
        )
    }

    public func mostPopularOpportunityCandidates(
        categoryID: String,
        regionCode: String,
        maxResults: Int = 12,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> [YouTubeOpportunityCandidate] {
        var components = URLComponents(
            string: "https://www.googleapis.com/youtube/v3/videos"
        )!
        var queryItems: [URLQueryItem] = [
            .init(
                name: "part",
                value: "snippet,statistics,status,contentDetails,liveStreamingDetails"
            ),
            .init(name: "chart", value: "mostPopular"),
            .init(name: "regionCode", value: regionCode),
            .init(
                name: "maxResults",
                value: String(min(max(maxResults, 1), 50))
            )
        ]
        if !categoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(.init(name: "videoCategoryId", value: categoryID))
        }
        components.queryItems = queryItems

        let data = try await perform(
            components.url!,
            session: session
        )
        let response = try JSONDecoder.youtube.decode(
            VideoListResponse.self,
            from: data
        )

        return response.items.compactMap { video in
            guard video.status?.embeddable != false,
                  let snippet = video.snippet else {
                return nil
            }
            return YouTubeOpportunityCandidate(
                videoID: video.id,
                title: Self.decodedYouTubeText(snippet.title),
                channelID: snippet.channelId,
                channelTitle: Self.decodedYouTubeText(snippet.channelTitle),
                publishedAt: snippet.publishedAt,
                thumbnailURL:
                    snippet.thumbnails?.medium?.url
                    ?? snippet.thumbnails?.defaultImage?.url,
                query:
                    "mostPopular:category:\(categoryID):region:\(regionCode)",
                retrievedAt: now,
                embeddable: video.status?.embeddable,
                contentKind: Self.contentKind(
                    video: video,
                    durationSeconds: Self.durationSeconds(
                        from: video.contentDetails?.duration
                    )
                ),
                durationSeconds: Self.durationSeconds(
                    from: video.contentDetails?.duration
                ),
                metrics: YouTubeOpportunityMetrics(
                    viewCount: video.statistics.flatMap {
                        Int($0.viewCount ?? "")
                    },
                    likeCount: video.statistics.flatMap {
                        Int($0.likeCount ?? "")
                    },
                    commentCount: video.statistics.flatMap {
                        Int($0.commentCount ?? "")
                    },
                    publishedAt: snippet.publishedAt,
                    retrievedAt: now
                )
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
            .init(
                name: "part",
                value: "statistics,status,contentDetails,liveStreamingDetails"
            ),
            .init(name: "id", value: ids.joined(separator: ","))
        ]
        let data = try await perform(c.url!, session: session)
        let response = try JSONDecoder.youtube.decode(VideoListResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.items.map { ($0.id, $0) })
    }

    private static func decodedYouTubeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func contentKind(
        video: VideoItem?,
        durationSeconds: Int?
    ) -> YouTubeOpportunityContentKind {
        if video?.liveStreamingDetails != nil {
            return .live
        }
        if let durationSeconds,
           durationSeconds > 0,
           durationSeconds <= 180 {
            return .short
        }
        return .video
    }

    private static func durationSeconds(
        from rawValue: String?
    ) -> Int? {
        guard let rawValue,
              rawValue.hasPrefix("PT") else {
            return nil
        }

        var digits = ""
        var total = 0
        for character in rawValue.dropFirst(2) {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let value = Int(digits) else {
                digits = ""
                continue
            }
            switch character {
            case "H": total += value * 3_600
            case "M": total += value * 60
            case "S": total += value
            default: break
            }
            digits = ""
        }
        return total > 0 ? total : nil
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
    let viewCount: String?
    let videoCount: String?
}
private struct ChannelContentDetails: Decodable {
    let relatedPlaylists: RelatedPlaylists
}
private struct RelatedPlaylists: Decodable {
    let uploads: String?
}

private struct VideoListResponse: Decodable {
    let items: [VideoItem]
}
private struct VideoItem: Decodable {
    let id: String
    let snippet: SearchSnippet?
    let statistics: VideoStatistics?
    let status: VideoStatus?
    let contentDetails: VideoContentDetails?
    let liveStreamingDetails: VideoLiveStreamingDetails?
}
private struct VideoContentDetails: Decodable {
    let duration: String?
}
private struct VideoLiveStreamingDetails: Decodable {
    let actualStartTime: Date?
    let scheduledStartTime: Date?
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

private struct SearchListResponse: Decodable { let items: [SearchItem]; let nextPageToken: String? }
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

public struct YouTubeOpportunityPage: Sendable {
    public let candidates: [YouTubeOpportunityCandidate]
    public let nextPageToken: String?

    public init(
        candidates: [YouTubeOpportunityCandidate],
        nextPageToken: String?
    ) {
        self.candidates = candidates
        self.nextPageToken = nextPageToken
    }
}
