import XCTest
@testable import BlackstockCore

final class CreatorQualityReviewTests: XCTestCase {
    func testUngroundedFindingCannotPassReleaseGate() {
        let review = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [],
            findings: [
                QualityFinding(
                    area: .packaging,
                    severity: .warning,
                    title: "Unbelegt",
                    explanation: "Diese Aussage hat keine Evidenz.",
                    recommendedAction: nil,
                    evidenceIDs: []
                )
            ],
            reviewedAt: Date()
        )
        XCTAssertFalse(review.passesReleaseGate)
        XCTAssertTrue(review.hasUngroundedFinding)
    }

    func testMissingRequiredAreaFailsCoverageGate() {
        let evidence = QualityEvidence(
            source: "Render-QA",
            observedFact: "Render geprüft.",
            reference: "render-1",
            observedAt: Date()
        )
        let review = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [evidence],
            findings: [
                QualityFinding(
                    area: .renderIntegrity,
                    severity: .info,
                    title: "Render geprüft",
                    explanation: "Render liegt vor.",
                    recommendedAction: nil,
                    evidenceIDs: [evidence.id]
                )
            ],
            reviewedAt: Date()
        )

        XCTAssertFalse(
            review.passesReleaseGate(
                requiredAreas: [.renderIntegrity, .packaging]
            )
        )
        XCTAssertEqual(
            review.missingCoverage(requiredAreas: [.renderIntegrity, .packaging]),
            [.packaging]
        )
    }

    func testGroundedWarningDoesNotBlockReleaseByItself() {
        let evidence = QualityEvidence(
            source: "Render-QA",
            observedFact: "Audio-Peak liegt unter Clipping-Grenze.",
            reference: "render-1",
            observedAt: Date()
        )
        let review = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [evidence],
            findings: [
                QualityFinding(
                    area: .audio,
                    severity: .warning,
                    title: "Leiser Abschnitt",
                    explanation: "Ein Abschnitt liegt deutlich unter dem restlichen Sprachpegel.",
                    recommendedAction: "Audio im markierten Bereich prüfen.",
                    evidenceIDs: [evidence.id]
                )
            ],
            reviewedAt: Date()
        )
        XCTAssertTrue(review.passesReleaseGate)
    }

    func testGroundedBlockerStopsRelease() {
        let evidence = QualityEvidence(
            source: "Rights Ledger",
            observedFact: "Für ein verwendetes Asset fehlt die Rechtefreigabe.",
            reference: "asset-42",
            observedAt: Date()
        )
        let review = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [evidence],
            findings: [
                QualityFinding(
                    area: .rightsAndPolicy,
                    severity: .blocker,
                    title: "Rechte fehlen",
                    explanation: "Dieses Asset darf noch nicht veröffentlicht werden.",
                    recommendedAction: "Lizenz nachweisen oder Asset ersetzen.",
                    evidenceIDs: [evidence.id]
                )
            ],
            reviewedAt: Date()
        )
        XCTAssertFalse(review.passesReleaseGate)
        XCTAssertEqual(review.blockingFindings.count, 1)
    }
}
