import Foundation

public enum GrowthObservationWindow: String, Codable, Sendable, CaseIterable {
    case first24Hours = "FIRST_24_HOURS"
    case first72Hours = "FIRST_72_HOURS"
    case first7Days = "FIRST_7_DAYS"
    case first28Days = "FIRST_28_DAYS"
}

public enum GrowthObjective: String, Codable, Sendable, CaseIterable {
    case views
    case watchTime
    case retention
    case subscribers
    case engagement
}

public struct PublishingExperiment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let targetChannelID: String
    public let hypothesis: String
    public let objective: GrowthObjective
    public let titleVariant: String
    public let thumbnailVariantID: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        targetChannelID: String,
        hypothesis: String,
        objective: GrowthObjective,
        titleVariant: String,
        thumbnailVariantID: String?,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.targetChannelID = targetChannelID
        self.hypothesis = hypothesis
        self.objective = objective
        self.titleVariant = titleVariant
        self.thumbnailVariantID = thumbnailVariantID
        self.createdAt = createdAt
    }
}

public struct PublishedVideoRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let experimentID: UUID?
    public let targetChannelID: String
    public let youtubeVideoID: String
    public let publishedAt: Date
    public var observations: [GrowthObservation]

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        experimentID: UUID?,
        targetChannelID: String,
        youtubeVideoID: String,
        publishedAt: Date,
        observations: [GrowthObservation] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.experimentID = experimentID
        self.targetChannelID = targetChannelID
        self.youtubeVideoID = youtubeVideoID
        self.publishedAt = publishedAt
        self.observations = observations
    }
}

public struct GrowthObservation: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let window: GrowthObservationWindow
    public let analytics: YouTubeAnalyticsSnapshot
    public let collectedAt: Date

    public init(
        id: UUID = UUID(),
        window: GrowthObservationWindow,
        analytics: YouTubeAnalyticsSnapshot,
        collectedAt: Date
    ) {
        self.id = id
        self.window = window
        self.analytics = analytics
        self.collectedAt = collectedAt
    }
}

public struct GrowthLearningRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let publishedVideoID: UUID
    public let experimentID: UUID?
    public let source: String
    public let observationIDs: [UUID]
    public let facts: [String]
    public let nextQuestion: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        publishedVideoID: UUID,
        experimentID: UUID?,
        source: String = "Blackstock",
        observationIDs: [UUID],
        facts: [String],
        nextQuestion: String?,
        createdAt: Date
    ) {
        self.id = id
        self.publishedVideoID = publishedVideoID
        self.experimentID = experimentID
        self.source = source
        self.observationIDs = observationIDs
        self.facts = facts
        self.nextQuestion = nextQuestion
        self.createdAt = createdAt
    }
}

public struct GrowthLearningEngine: Sendable {
    public init() {}

    public func summarize(_ record: PublishedVideoRecord) -> GrowthLearningRecord? {
        guard let latest = record.observations.max(by: { $0.collectedAt < $1.collectedAt }) else {
            return nil
        }

        var facts: [String] = []
        let a = latest.analytics

        if let value = a.views { facts.append("YouTube meldet \(value) Views im abgefragten YouTube-Analytics-Zeitraum.") }
        if let value = a.estimatedMinutesWatched { facts.append("YouTube meldet \(Int(value.rounded())) Minuten Wiedergabezeit.") }
        if let value = a.averageViewDuration { facts.append("YouTube meldet \(Int(value.rounded())) Sekunden durchschnittliche Wiedergabedauer.") }
        if let value = a.averageViewPercentage { facts.append("YouTube meldet \(String(format: "%.1f", value)) % durchschnittlich angesehene Videodauer.") }
        if let value = a.subscribersGained { facts.append("YouTube meldet \(value) gewonnene Abonnenten.") }
        if let value = a.subscribersLost { facts.append("YouTube meldet \(value) verlorene Abonnenten.") }

        facts.append(
            "Analytics-Zeitraum: \(a.requestedStartDate) bis \(a.requestedEndDate); Datenabruf: \(a.retrievedAt.formatted(date: .abbreviated, time: .shortened)). YouTube-Analytics können verzögert sein."
        )

        return GrowthLearningRecord(
            publishedVideoID: record.id,
            experimentID: record.experimentID,
            observationIDs: record.observations.map(\.id),
            facts: facts,
            nextQuestion: "Welche einzelne Hypothese soll beim nächsten Video gezielt getestet werden?",
            createdAt: Date()
        )
    }
}
