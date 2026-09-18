import Foundation

public enum CreatorQualityArea: String, Codable, Sendable, CaseIterable {
    case demandFit = "DEMAND_FIT"
    case packaging = "PACKAGING"
    case retentionStructure = "RETENTION_STRUCTURE"
    case audio = "AUDIO"
    case captions = "CAPTIONS"
    case visualComposition = "VISUAL_COMPOSITION"
    case rightsAndPolicy = "RIGHTS_AND_POLICY"
    case renderIntegrity = "RENDER_INTEGRITY"
}

public enum QualityFindingSeverity: String, Codable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case blocker = "BLOCKER"
}

public struct QualityEvidence: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let source: String
    public let observedFact: String
    public let reference: String?
    public let observedAt: Date

    public init(
        id: UUID = UUID(),
        source: String,
        observedFact: String,
        reference: String?,
        observedAt: Date
    ) {
        self.id = id
        self.source = source
        self.observedFact = observedFact
        self.reference = reference
        self.observedAt = observedAt
    }
}

public struct QualityFinding: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let area: CreatorQualityArea
    public let severity: QualityFindingSeverity
    public let title: String
    public let explanation: String
    public let recommendedAction: String?
    public let evidenceIDs: [UUID]

    public init(
        id: UUID = UUID(),
        area: CreatorQualityArea,
        severity: QualityFindingSeverity,
        title: String,
        explanation: String,
        recommendedAction: String?,
        evidenceIDs: [UUID]
    ) {
        self.id = id
        self.area = area
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.recommendedAction = recommendedAction
        self.evidenceIDs = evidenceIDs
    }

    public var isGrounded: Bool {
        !evidenceIDs.isEmpty
    }
}

public struct CreatorQualityReview: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let stage: BlackstockStage
    public let evidence: [QualityEvidence]
    public let findings: [QualityFinding]
    public let reviewedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        stage: BlackstockStage,
        evidence: [QualityEvidence],
        findings: [QualityFinding],
        reviewedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.stage = stage
        self.evidence = evidence
        self.findings = findings
        self.reviewedAt = reviewedAt
    }

    public var hasUngroundedFinding: Bool {
        findings.contains { !$0.isGrounded }
    }

    public var blockingFindings: [QualityFinding] {
        findings.filter { $0.severity == .blocker }
    }

    public var passesReleaseGate: Bool {
        !hasUngroundedFinding && blockingFindings.isEmpty
    }

    public func findings(in area: CreatorQualityArea) -> [QualityFinding] {
        findings.filter { $0.area == area }
    }
}
