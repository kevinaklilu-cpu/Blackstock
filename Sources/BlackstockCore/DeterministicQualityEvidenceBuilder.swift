import Foundation

public struct DeterministicQualityEvidenceBuilder: Sendable {
    public init() {}

    public func build(
        projectID: UUID,
        asset: ProductionMediaAsset,
        artifact: RenderArtifact,
        reviewedAt: Date = Date()
    ) -> CreatorQualityReview {
        var evidence: [QualityEvidence] = []
        var findings: [QualityFinding] = []

        let rightsEvidence = QualityEvidence(
            source: "Rights Ledger",
            observedFact: asset.mayEnterProduction
                ? "Produktionsmedium besitzt Rechtebestätigung und Nachweis."
                : "Produktionsmedium besitzt keine ausreichende Rechtefreigabe.",
            reference: asset.id.uuidString,
            observedAt: reviewedAt
        )
        evidence.append(rightsEvidence)
        findings.append(
            QualityFinding(
                area: .rightsAndPolicy,
                severity: asset.mayEnterProduction ? .info : .blocker,
                title: asset.mayEnterProduction
                    ? "Rechte-Nachweis vorhanden"
                    : "Rechte-Nachweis unvollständig",
                explanation: rightsEvidence.observedFact,
                recommendedAction: asset.mayEnterProduction
                    ? nil
                    : "Rechte bestätigen oder Medium ersetzen.",
                evidenceIDs: [rightsEvidence.id]
            )
        )

        let renderEvidence = QualityEvidence(
            source: "Render Artifact",
            observedFact: artifact.validated
                ? "Lokaler Render wurde erzeugt und als nicht-leeres Artefakt validiert."
                : "Render-Artefakt ist nicht validiert.",
            reference: artifact.id.uuidString,
            observedAt: reviewedAt
        )
        evidence.append(renderEvidence)
        findings.append(
            QualityFinding(
                area: .renderIntegrity,
                severity: artifact.validated ? .info : .blocker,
                title: artifact.validated
                    ? "Render-Artefakt vorhanden"
                    : "Render-Artefakt ungültig",
                explanation: renderEvidence.observedFact,
                recommendedAction: artifact.validated
                    ? nil
                    : "Video erneut rendern.",
                evidenceIDs: [renderEvidence.id]
            )
        )

        return CreatorQualityReview(
            projectID: projectID,
            stage: .review,
            evidence: evidence,
            findings: findings,
            reviewedAt: reviewedAt
        )
    }
}
