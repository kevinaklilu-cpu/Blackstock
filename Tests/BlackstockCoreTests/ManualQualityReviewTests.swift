import XCTest
@testable import BlackstockCore

final class ManualQualityReviewTests: XCTestCase {
    func testManualAttestationCoversOnlyAllowedQualitativeArea() {
        let automatic = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [],
            findings: [],
            reviewedAt: Date()
        )
        let attestation = ManualQualityAttestation(
            area: .packaging,
            note: "Titel und Thumbnail stimmen mit dem tatsächlichen Video-Versprechen überein.",
            confirmedAt: Date()
        )

        let review = QualityReviewComposer().compose(
            automatic: automatic,
            manualAttestations: [attestation]
        )

        XCTAssertTrue(review.coveredAreas.contains(.packaging))
        XCTAssertEqual(review.findings(in: .packaging).count, 1)
    }

    func testRightsCannotBeManuallyOverridden() {
        let automatic = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [],
            findings: [],
            reviewedAt: Date()
        )
        let invalid = ManualQualityAttestation(
            area: .rightsAndPolicy,
            note: "Ich habe es geprüft.",
            confirmedAt: Date()
        )

        let review = QualityReviewComposer().compose(
            automatic: automatic,
            manualAttestations: [invalid]
        )

        XCTAssertFalse(invalid.isValid)
        XCTAssertFalse(review.coveredAreas.contains(.rightsAndPolicy))
    }

    func testManualEvidenceDoesNotRemoveAutomaticBlocker() {
        let evidence = QualityEvidence(
            source: "Rights Ledger",
            observedFact: "Rechte fehlen.",
            reference: "asset-1",
            observedAt: Date()
        )
        let automatic = CreatorQualityReview(
            projectID: UUID(),
            stage: .review,
            evidence: [evidence],
            findings: [
                QualityFinding(
                    area: .rightsAndPolicy,
                    severity: .blocker,
                    title: "Rechte fehlen",
                    explanation: "Rechte fehlen.",
                    recommendedAction: "Asset ersetzen.",
                    evidenceIDs: [evidence.id]
                )
            ],
            reviewedAt: Date()
        )
        let manual = ManualQualityAttestation(
            area: .packaging,
            note: "Packaging geprüft.",
            confirmedAt: Date()
        )

        let review = QualityReviewComposer().compose(
            automatic: automatic,
            manualAttestations: [manual]
        )

        XCTAssertEqual(review.blockingFindings.count, 1)
        XCTAssertFalse(review.passesReleaseGate)
    }

    func testEmptyManualNoteDoesNotCountAsEvidence() {
        let attestation = ManualQualityAttestation(
            area: .audio,
            note: "   ",
            confirmedAt: Date()
        )
        XCTAssertFalse(attestation.isValid)
    }
}
