import Foundation

public enum OpportunityClipPreparationStatus:
    String,
    Codable,
    Sendable,
    Equatable {
    case resolvingSource = "RESOLVING_SOURCE"
    case productionMediaRequired = "PRODUCTION_MEDIA_REQUIRED"
    case localProcessingReady = "LOCAL_PROCESSING_READY"
    case generatingClips = "GENERATING_CLIPS"
    case clipsAvailable = "CLIPS_AVAILABLE"

    public var germanTitle: String {
        switch self {
        case .resolvingSource:
            return "Quelle wird aufgelöst"
        case .productionMediaRequired:
            return "Produktionsvideo erforderlich"
        case .localProcessingReady:
            return "Bereit für lokalen Schnitt"
        case .generatingClips:
            return "Clips werden lokal erzeugt"
        case .clipsAvailable:
            return "Clips verfügbar"
        }
    }
}

public struct OpportunityClipPreparationSnapshot:
    Codable,
    Sendable,
    Equatable {
    public let sourceID: UUID
    public let status: OpportunityClipPreparationStatus
    public let explanation: String
    public let clipCount: Int
    public let observedAt: Date

    public init(
        sourceID: UUID,
        status: OpportunityClipPreparationStatus,
        explanation: String,
        clipCount: Int,
        observedAt: Date
    ) {
        self.sourceID = sourceID
        self.status = status
        self.explanation = explanation
        self.clipCount = max(clipCount, 0)
        self.observedAt = observedAt
    }
}

public struct OpportunityClipPreparationPlanner: Sendable {
    public init() {}

    public func snapshot(
        source: MediaSourceReference,
        resolution: ResolvedMediaSource,
        hasBoundAuthorizedMedia: Bool,
        isGeneratingClips: Bool,
        clipCount: Int,
        observedAt: Date = Date()
    ) -> OpportunityClipPreparationSnapshot {
        let count = max(clipCount, 0)

        if isGeneratingClips && hasBoundAuthorizedMedia {
            return .init(
                sourceID: source.id,
                status: .generatingClips,
                explanation:
                    "Blackstock transkribiert und segmentiert das gebundene Produktionsvideo lokal auf diesem Mac.",
                clipCount: count,
                observedAt: observedAt
            )
        }

        if hasBoundAuthorizedMedia && count > 0 {
            return .init(
                sourceID: source.id,
                status: .clipsAvailable,
                explanation:
                    "\(count) lokale Clip-Kandidaten sind bereit zur Vorschau und non-destruktiven Bearbeitung.",
                clipCount: count,
                observedAt: observedAt
            )
        }

        if hasBoundAuthorizedMedia {
            return .init(
                sourceID: source.id,
                status: .localProcessingReady,
                explanation:
                    "Das Produktionsvideo ist automatisch mit der Opportunity verknüpft und kann lokal analysiert und geschnitten werden.",
                clipCount: count,
                observedAt: observedAt
            )
        }

        if resolution.status == .ingestReady {
            return .init(
                sourceID: source.id,
                status: .resolvingSource,
                explanation:
                    "Ein freigegebener Ingest-Pfad ist verfügbar. Blackstock wartet auf das materialisierte Produktionsmedium, bevor der lokale Schnitt beginnt.",
                clipCount: count,
                observedAt: observedAt
            )
        }

        return .init(
            sourceID: source.id,
            status: .productionMediaRequired,
            explanation:
                "Das YouTube-Video bleibt direkt in Blackstock ausgewählt. Für den Schnitt fehlt noch eine zulässige Videodatei; ein versteckter oder nicht freigegebener Download wird nicht gestartet.",
            clipCount: count,
            observedAt: observedAt
        )
    }
}
