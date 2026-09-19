import Foundation

public enum ChannelStrategyDraftError: Error, Sendable, Equatable {
    case missingPrimaryTopic
    case missingContentPromise
    case missingAudienceHypothesis
    case missingPillars
}

public struct ChannelStrategyDraft: Sendable, Equatable {
    public var primaryTopic: String
    public var contentPromise: String
    public var audienceHypothesis: String
    public var pillarsText: String
    public var adjacentTopicsText: String
    public var excludedTopicsText: String
    public var objective: StrategicObjective

    public init(
        primaryTopic: String,
        contentPromise: String,
        audienceHypothesis: String,
        pillarsText: String,
        adjacentTopicsText: String,
        excludedTopicsText: String,
        objective: StrategicObjective
    ) {
        self.primaryTopic = primaryTopic
        self.contentPromise = contentPromise
        self.audienceHypothesis = audienceHypothesis
        self.pillarsText = pillarsText
        self.adjacentTopicsText = adjacentTopicsText
        self.excludedTopicsText = excludedTopicsText
        self.objective = objective
    }

    public func makeStrategy(
        channelID: String,
        contentLanguage: String,
        version: Int,
        now: Date = Date()
    ) throws -> ChannelStrategy {
        let topic = primaryTopic.cleaned
        guard !topic.isEmpty else {
            throw ChannelStrategyDraftError.missingPrimaryTopic
        }

        let promise = contentPromise.cleaned
        guard !promise.isEmpty else {
            throw ChannelStrategyDraftError.missingContentPromise
        }

        let audience = audienceHypothesis.cleaned
        guard !audience.isEmpty else {
            throw ChannelStrategyDraftError.missingAudienceHypothesis
        }

        let pillars = Self.list(from: pillarsText)
        guard !pillars.isEmpty else {
            throw ChannelStrategyDraftError.missingPillars
        }

        return ChannelStrategy(
            channelID: channelID,
            primaryTopic: topic,
            topicDefinition: topic,
            contentPromise: promise,
            pillars: pillars,
            adjacentTopics: Self.list(from: adjacentTopicsText),
            excludedTopics: Self.list(from: excludedTopicsText),
            defaultContentLanguage: contentLanguage,
            researchLanguages: contentLanguage == "de"
                ? ["de", "en"]
                : [contentLanguage],
            audienceHypothesis: audience,
            objectives: [objective],
            explorationPolicy: .init(),
            effectiveFrom: now,
            version: version
        )
    }

    public static func list(from value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map(\.cleaned)
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
    }
}

private extension String {
    var cleaned: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element == String {
    func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter {
            let key = $0.lowercased()
            return seen.insert(key).inserted
        }
    }
}
