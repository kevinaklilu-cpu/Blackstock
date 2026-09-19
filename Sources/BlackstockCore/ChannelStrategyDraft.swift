import Foundation

public enum ChannelStrategyDraftValidationError: Error, Sendable, Equatable {
    case missingPrimaryTopic
    case missingTopicDefinition
    case missingContentPromise
    case missingAudienceHypothesis
    case missingPillars
}

public struct ChannelStrategyDraft: Sendable, Equatable {
    public var primaryTopic: String
    public var topicDefinition: String
    public var contentPromise: String
    public var pillars: [String]
    public var adjacentTopics: [String]
    public var excludedTopics: [String]
    public var audienceHypothesis: String
    public var objective: StrategicObjective

    public init(
        primaryTopic: String,
        topicDefinition: String,
        contentPromise: String,
        pillars: [String],
        adjacentTopics: [String] = [],
        excludedTopics: [String] = [],
        audienceHypothesis: String,
        objective: StrategicObjective = .balanced
    ) {
        self.primaryTopic = primaryTopic
        self.topicDefinition = topicDefinition
        self.contentPromise = contentPromise
        self.pillars = pillars
        self.adjacentTopics = adjacentTopics
        self.excludedTopics = excludedTopics
        self.audienceHypothesis = audienceHypothesis
        self.objective = objective
    }

    public func validate() throws {
        guard !Self.normalized(primaryTopic).isEmpty else {
            throw ChannelStrategyDraftValidationError.missingPrimaryTopic
        }
        guard !Self.normalized(topicDefinition).isEmpty else {
            throw ChannelStrategyDraftValidationError.missingTopicDefinition
        }
        guard !Self.normalized(contentPromise).isEmpty else {
            throw ChannelStrategyDraftValidationError.missingContentPromise
        }
        guard !Self.normalized(audienceHypothesis).isEmpty else {
            throw ChannelStrategyDraftValidationError.missingAudienceHypothesis
        }
        guard !Self.normalizedList(pillars).isEmpty else {
            throw ChannelStrategyDraftValidationError.missingPillars
        }
    }

    public func makeStrategy(
        channelID: String,
        defaultContentLanguage: String,
        researchLanguages: [String],
        explorationPolicy: ExplorationPolicy = .init(),
        effectiveFrom: Date,
        version: Int
    ) throws -> ChannelStrategy {
        try validate()

        return ChannelStrategy(
            channelID: Self.normalized(channelID),
            primaryTopic: Self.normalized(primaryTopic),
            topicDefinition: Self.normalized(topicDefinition),
            contentPromise: Self.normalized(contentPromise),
            pillars: Self.normalizedList(pillars),
            adjacentTopics: Self.normalizedList(adjacentTopics),
            excludedTopics: Self.normalizedList(excludedTopics),
            defaultContentLanguage: Self.normalized(defaultContentLanguage),
            researchLanguages: Self.normalizedList(researchLanguages),
            audienceHypothesis: Self.normalized(audienceHypothesis),
            objectives: [objective],
            explorationPolicy: explorationPolicy,
            effectiveFrom: effectiveFrom,
            version: version
        )
    }

    public static func parseList(_ value: String) -> [String] {
        normalizedList(
            value
                .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = normalized(raw)
            guard !value.isEmpty else { return nil }
            let key = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard seen.insert(key).inserted else { return nil }
            return value
        }
    }
}
