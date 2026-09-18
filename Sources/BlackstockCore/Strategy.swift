import Foundation

public enum StrategicObjective: String, Codable, Sendable, CaseIterable { case balanced, reach, watchTime, subscribers, revenue }

public struct HistoricalChannelProfile: Codable, Sendable, Equatable {
    public var observedTopics: [String]
    public var observedLanguages: [String]
    public var observedFormats: [String]
    public var observedAt: Date
}

public struct ExplorationPolicy: Codable, Sendable, Equatable {
    public var core: Double
    public var adjacent: Double
    public var exploration: Double
    public init(core: Double = 0.70, adjacent: Double = 0.20, exploration: Double = 0.10) {
        let total = max(core + adjacent + exploration, 0.0001)
        self.core = core / total; self.adjacent = adjacent / total; self.exploration = exploration / total
    }
}

public struct ChannelStrategy: Codable, Sendable, Equatable {
    public let channelID: String
    public var primaryTopic: String
    public var topicDefinition: String
    public var contentPromise: String
    public var pillars: [String]
    public var adjacentTopics: [String]
    public var excludedTopics: [String]
    public var defaultContentLanguage: String
    public var researchLanguages: [String]
    public var audienceHypothesis: String
    public var objectives: [StrategicObjective]
    public var explorationPolicy: ExplorationPolicy
    public var effectiveFrom: Date
    public var version: Int
}

public struct ContentLanguageStrategy: Codable, Sendable, Equatable {
    public var sourceLanguage: String
    public var primaryOutputLanguage: String
    public var titleLanguage: String
    public var descriptionLanguage: String
    public var thumbnailTextLanguage: String
    public var captionLanguage: String
    public var audioLanguage: String
    public var chapterLanguage: String
    public var metadataLanguage: String
}