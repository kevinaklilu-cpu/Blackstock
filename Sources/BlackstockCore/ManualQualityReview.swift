import Foundation

public struct ManualQualityAttestation: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let area: CreatorQualityArea
    public let note: String
    public let confirmedAt: Date

    public init(
        id: UUID = UUID(),
        area: CreatorQualityArea,
        note: String,
        confirmedAt: Date
    ) {
        self.id = id
        self.area = area
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.confirmedAt = confirmedAt
    }

    public var isValid: Bool {
        Self.manuallyReviewableAreas.contains(area) && !note.isEmpty
    }

    public static let manuallyReviewableAreas: Set<CreatorQualityArea> = [
        .packaging,
        .retentionStructure,
        .audio,
        .captions,
        .visualComposition
    ]
}

public struct QualityReviewComposer: Sendable {
    public init() {}

    public func compose(
        automatic: CreatorQualityReview,
        manualAttestations: [ManualQualityAttestation],
        reviewedAt: Date = Date()
    ) -> CreatorQualityReview {
        var evidence = automatic.evidence
        var findings = automatic.findings

        for attestation in manualAttestations where attestation.isValid {
            let item = QualityEvidence(
                source: "User Review",
                observedFact: attestation.note,
                reference: attestation.id.uuidString,
                observedAt: attestation.confirmedAt
            )
            evidence.append(item)
            findings.append(
                QualityFinding(
                    area: attestation.area,
                    severity: .info,
                    title: "Manuell geprüft",
                    explanation: attestation.note,
                    recommendedAction: nil,
                    evidenceIDs: [item.id]
                )
            )
        }

        return CreatorQualityReview(
            projectID: automatic.projectID,
            stage: automatic.stage,
            evidence: evidence,
            findings: findings,
            reviewedAt: reviewedAt
        )
    }
}
