import Foundation

public enum GroundingStrength: String, Codable, Sendable {
    case grounded
    case partial
    case insufficient
}

public struct EvidenceReference: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let sourceID: String
    public let sourceURL: URL?
    public let statement: String
    public let observedAt: Date
    public let startSeconds: Double?
    public let endSeconds: Double?

    public init(
        id: UUID = UUID(),
        sourceID: String,
        sourceURL: URL?,
        statement: String,
        observedAt: Date,
        startSeconds: Double? = nil,
        endSeconds: Double? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.statement = statement
        self.observedAt = observedAt
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

public struct RecommendationTrace: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let rationale: [String]
    public let limitations: [String]
    public let evidenceIDs: [UUID]
    public let grounding: GroundingStrength
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        rationale: [String],
        limitations: [String],
        evidenceIDs: [UUID],
        grounding: GroundingStrength,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.limitations = limitations
        self.evidenceIDs = evidenceIDs
        self.grounding = grounding
        self.createdAt = createdAt
    }

    public var mayBePresentedAsRecommendation: Bool {
        grounding == .grounded && !rationale.isEmpty && !evidenceIDs.isEmpty
    }
}

public enum ActivityActor: String, Codable, Sendable {
    case user
    case blackstock
    case provider
}

public struct ActivityEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let actor: ActivityActor
    public let stage: BlackstockStage
    public let action: String
    public let summary: String
    public let relatedSourceIDs: [String]
    public let relatedEvidenceIDs: [UUID]
    public let beforeRevisionID: UUID?
    public let afterRevisionID: UUID?
    public let reversible: Bool
    public let correlationID: UUID

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        actor: ActivityActor,
        stage: BlackstockStage,
        action: String,
        summary: String,
        relatedSourceIDs: [String] = [],
        relatedEvidenceIDs: [UUID] = [],
        beforeRevisionID: UUID? = nil,
        afterRevisionID: UUID? = nil,
        reversible: Bool,
        correlationID: UUID = UUID()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.stage = stage
        self.action = action
        self.summary = summary
        self.relatedSourceIDs = relatedSourceIDs
        self.relatedEvidenceIDs = relatedEvidenceIDs
        self.beforeRevisionID = beforeRevisionID
        self.afterRevisionID = afterRevisionID
        self.reversible = reversible
        self.correlationID = correlationID
    }
}

public struct ActivityLedger: Codable, Sendable, Equatable {
    public private(set) var events: [ActivityEvent]

    public init(events: [ActivityEvent] = []) {
        self.events = events.sorted { $0.timestamp < $1.timestamp }
    }

    public mutating func append(_ event: ActivityEvent) {
        events.append(event)
        events.sort { $0.timestamp < $1.timestamp }
    }

    public func events(correlationID: UUID) -> [ActivityEvent] {
        events.filter { $0.correlationID == correlationID }
    }
}
