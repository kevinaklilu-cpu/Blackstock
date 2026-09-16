import Foundation

public struct ChannelSnapshot: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subscriberCount: Int
    public var medianViews: Double
    public var medianViewsPerHour: Double
    public var recentTopics: [String]

    public init(id: String, title: String, subscriberCount: Int = 0, medianViews: Double = 1, medianViewsPerHour: Double = 1, recentTopics: [String] = []) {
        self.id = id
        self.title = title
        self.subscriberCount = subscriberCount
        self.medianViews = max(medianViews, 1)
        self.medianViewsPerHour = max(medianViewsPerHour, 1)
        self.recentTopics = recentTopics
    }
}

public enum VideoFormat: String, Codable, Sendable, CaseIterable {
    case short
    case longform
    public static func infer(durationSeconds: Int) -> VideoFormat { durationSeconds <= 180 ? .short : .longform }
}

public enum VideoDurationFilter: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, upToOne, oneToFour, fourToTen, tenToTwenty, twentyToSixty, overSixty
    public var id: String { rawValue }
    public func contains(seconds: Int) -> Bool {
        switch self {
        case .all: return true
        case .upToOne: return seconds < 60
        case .oneToFour: return seconds >= 60 && seconds < 240
        case .fourToTen: return seconds >= 240 && seconds < 600
        case .tenToTwenty: return seconds >= 600 && seconds < 1200
        case .twentyToSixty: return seconds >= 1200 && seconds < 3600
        case .overSixty: return seconds >= 3600
        }
    }
}

public struct VideoMetric: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var channelID: String
    public var channelTitle: String
    public var publishedAt: Date
    public var durationSeconds: Int
    public var viewCount: Int
    public var likeCount: Int?
    public var commentCount: Int?
    public var thumbnailURL: URL?
    public var tags: [String]

    public init(id: String, title: String, channelID: String, channelTitle: String, publishedAt: Date, durationSeconds: Int, viewCount: Int, likeCount: Int? = nil, commentCount: Int? = nil, thumbnailURL: URL? = nil, tags: [String] = []) {
        self.id = id; self.title = title; self.channelID = channelID; self.channelTitle = channelTitle; self.publishedAt = publishedAt; self.durationSeconds = durationSeconds; self.viewCount = viewCount; self.likeCount = likeCount; self.commentCount = commentCount; self.thumbnailURL = thumbnailURL; self.tags = tags
    }
    public var ageHours: Double { max(Date().timeIntervalSince(publishedAt) / 3600, 0.25) }
    public var viewsPerHour: Double { Double(viewCount) / ageHours }
    public var format: VideoFormat { .infer(durationSeconds: durationSeconds) }
}

public enum SignalStrength: String, Codable, Sendable { case high, medium, low }

public struct TrendReason: Codable, Identifiable, Sendable, Equatable {
    public var id: String { key }
    public let key: String
    public let label: String
    public let strength: SignalStrength
    public init(key: String, label: String, strength: SignalStrength) { self.key = key; self.label = label; self.strength = strength }
}

public struct TrendSignal: Codable, Identifiable, Sendable, Equatable {
    public var id: String { video.id }
    public let video: VideoMetric
    public let reasons: [TrendReason]
    public let recommendedFormat: VideoFormat
    public let rankValue: Double
    public let topic: String
    public init(video: VideoMetric, reasons: [TrendReason], recommendedFormat: VideoFormat, rankValue: Double, topic: String) { self.video = video; self.reasons = reasons; self.recommendedFormat = recommendedFormat; self.rankValue = rankValue; self.topic = topic }
}

public struct TrendPage: Sendable, Equatable {
    public let items: [TrendSignal]
    public let nextPageToken: String?
    public init(items: [TrendSignal], nextPageToken: String?) { self.items = items; self.nextPageToken = nextPageToken }
}

public struct Project: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var sourceVideoID: String?
    public var localMediaURL: URL?
    public var targetFormat: VideoFormat
    public var transcript: String
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, sourceVideoID: String? = nil, localMediaURL: URL? = nil, targetFormat: VideoFormat = .short, transcript: String = "", notes: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.sourceVideoID = sourceVideoID; self.localMediaURL = localMediaURL; self.targetFormat = targetFormat; self.transcript = transcript; self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct AnalyticsSnapshot: Codable, Sendable, Equatable {
    public var views: Int
    public var watchTimeMinutes: Double
    public var impressions: Int
    public var clickThroughRate: Double?
    public var averageViewDurationSeconds: Double?
    public init(views: Int = 0, watchTimeMinutes: Double = 0, impressions: Int = 0, clickThroughRate: Double? = nil, averageViewDurationSeconds: Double? = nil) { self.views = views; self.watchTimeMinutes = watchTimeMinutes; self.impressions = impressions; self.clickThroughRate = clickThroughRate; self.averageViewDurationSeconds = averageViewDurationSeconds }
}
