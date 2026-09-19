import Foundation

public enum YouTubeAnalyticsCompleteness: String, Codable, Sendable {
    case providerMayLag = "PROVIDER_MAY_LAG"
}

public struct YouTubeAnalyticsSnapshot: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let channelID: String
    public let videoID: String?
    public let startDate: String
    public let endDate: String
    public let retrievedAt: Date
    public let views: Int?
    public let engagedViews: Int?
    public let likes: Int?
    public let comments: Int?
    public let shares: Int?
    public let estimatedMinutesWatched: Double?
    public let averageViewDuration: Double?
    public let averageViewPercentage: Double?
    public let subscribersGained: Int?
    public let subscribersLost: Int?

    public init(
        id: UUID = UUID(),
        channelID: String,
        videoID: String?,
        startDate: String,
        endDate: String,
        retrievedAt: Date,
        views: Int?,
        engagedViews: Int?,
        likes: Int?,
        comments: Int?,
        shares: Int?,
        estimatedMinutesWatched: Double?,
        averageViewDuration: Double?,
        averageViewPercentage: Double?,
        subscribersGained: Int?,
        subscribersLost: Int?
    ) {
        self.id = id
        self.channelID = channelID
        self.videoID = videoID
        self.startDate = startDate
        self.endDate = endDate
        self.retrievedAt = retrievedAt
        self.views = views
        self.engagedViews = engagedViews
        self.likes = likes
        self.comments = comments
        self.shares = shares
        self.estimatedMinutesWatched = estimatedMinutesWatched
        self.averageViewDuration = averageViewDuration
        self.averageViewPercentage = averageViewPercentage
        self.subscribersGained = subscribersGained
        self.subscribersLost = subscribersLost
    }

    public var temporalSemantic: TemporalSemantic {
        .analyticsPeriod
    }

    public var completeness: YouTubeAnalyticsCompleteness {
        .providerMayLag
    }

    public var requestedStartDate: String { startDate }
    public var requestedEndDate: String { endDate }

    public var netSubscribers: Int? {
        guard let gained = subscribersGained, let lost = subscribersLost else { return nil }
        return gained - lost
    }
}

public enum YouTubeAnalyticsAPIError: Error, Sendable, Equatable {
    case invalidResponse
    case api(Int)
    case missingRow
    case malformedResponse
}

public struct YouTubeAnalyticsClient: Sendable {
    public let accessToken: String
    public let channelID: String

    public init(accessToken: String, channelID: String) {
        self.accessToken = accessToken
        self.channelID = channelID
    }

    public func snapshot(
        startDate: String,
        endDate: String,
        videoID: String? = nil,
        session: URLSession = .shared,
        now: Date = Date()
    ) async throws -> YouTubeAnalyticsSnapshot {
        let request = snapshotRequest(
            startDate: startDate,
            endDate: endDate,
            videoID: videoID
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAnalyticsAPIError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw YouTubeAnalyticsAPIError.api(http.statusCode)
        }

        return try decodeSnapshot(
            data,
            startDate: startDate,
            endDate: endDate,
            videoID: videoID,
            retrievedAt: now
        )
    }

    func snapshotRequest(
        startDate: String,
        endDate: String,
        videoID: String?
    ) -> URLRequest {
        let metricNames = [
            "views",
            "engagedViews",
            "likes",
            "comments",
            "shares",
            "estimatedMinutesWatched",
            "averageViewDuration",
            "averageViewPercentage",
            "subscribersGained",
            "subscribersLost"
        ]

        var components = URLComponents(
            string: "https://youtubeanalytics.googleapis.com/v2/reports"
        )!
        var items: [URLQueryItem] = [
            .init(name: "ids", value: "channel==MINE"),
            .init(name: "startDate", value: startDate),
            .init(name: "endDate", value: endDate),
            .init(
                name: "metrics",
                value: metricNames.joined(separator: ",")
            )
        ]
        if let videoID,
           !videoID.trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            items.append(
                .init(
                    name: "filters",
                    value: "video==\(videoID)"
                )
            )
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    func decodeSnapshot(
        _ data: Data,
        startDate: String,
        endDate: String,
        videoID: String?,
        retrievedAt: Date
    ) throws -> YouTubeAnalyticsSnapshot {
        let decoded = try JSONDecoder().decode(
            AnalyticsResponse.self,
            from: data
        )
        guard let row = decoded.rows?.first else {
            throw YouTubeAnalyticsAPIError.missingRow
        }

        let names = decoded.columnHeaders.map(\.name)
        guard names.count == row.count else {
            throw YouTubeAnalyticsAPIError.malformedResponse
        }
        let values = Dictionary(
            uniqueKeysWithValues: zip(names, row)
        )

        return YouTubeAnalyticsSnapshot(
            channelID: channelID,
            videoID: videoID,
            startDate: startDate,
            endDate: endDate,
            retrievedAt: retrievedAt,
            views: values.int("views"),
            engagedViews: values.int("engagedViews"),
            likes: values.int("likes"),
            comments: values.int("comments"),
            shares: values.int("shares"),
            estimatedMinutesWatched: values.double(
                "estimatedMinutesWatched"
            ),
            averageViewDuration: values.double(
                "averageViewDuration"
            ),
            averageViewPercentage: values.double(
                "averageViewPercentage"
            ),
            subscribersGained: values.int(
                "subscribersGained"
            ),
            subscribersLost: values.int(
                "subscribersLost"
            )
        )
    }
}

private struct AnalyticsResponse: Decodable {
    let columnHeaders: [AnalyticsColumnHeader]
    let rows: [[AnalyticsScalar]]?
}

private struct AnalyticsColumnHeader: Decodable {
    let name: String
}

private enum AnalyticsScalar: Decodable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        case .bool, .null: return nil
        }
    }
}

private extension Dictionary where Key == String, Value == AnalyticsScalar {
    func int(_ key: String) -> Int? {
        self[key]?.doubleValue.map { Int($0.rounded()) }
    }

    func double(_ key: String) -> Double? {
        self[key]?.doubleValue
    }
}
