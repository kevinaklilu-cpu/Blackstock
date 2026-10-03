import XCTest
@testable import BlackstockCore

final class AutomaticPublishReviewTests: XCTestCase {
    func testTechnicalReviewNeedsNoEditorialNotesAndAllowsNoCaptionTrack() {
        let (base, package) = fixture()
        let result = AutomaticPublishReview().build(base: base, package: package)
        XCTAssertTrue(result.passesReleaseGate(requiredAreas: AutomaticPublishReview.requiredAreas))
        XCTAssertFalse(result.coveredAreas.contains(.retentionStructure))
        XCTAssertFalse(result.coveredAreas.contains(.visualComposition))
        XCTAssertTrue(result.evidence.allSatisfy { $0.source != "User Review" })
    }

    func testAutomaticPreparationDoesNotHideAudioBlockers() {
        let (base, package) = fixture(audioBlocked: true)
        let result = AutomaticPublishReview().build(base: base, package: package)
        XCTAssertFalse(result.passesReleaseGate(requiredAreas: AutomaticPublishReview.requiredAreas))
        XCTAssertEqual(result.blockingFindings.map(\.area), [.audio])
    }

    func testInvalidTitleBlocksUploadWithoutPretendingItWasReviewed() {
        let (base, package) = fixture(title: String(repeating: "x", count: 101))
        let result = AutomaticPublishReview().build(base: base, package: package)
        XCTAssertTrue(result.blockingFindings.contains { $0.area == .packaging })
    }

    private func fixture(title: String = "Video", audioBlocked: Bool = false) -> (CreatorQualityReview, PublishPackage) {
        let projectID = UUID()
        let evidence = QualityEvidence(source: "Test measurement", observedFact: "Technical fixture",
            reference: nil, observedAt: Date())
        let base = CreatorQualityReview(projectID: projectID, stage: .review, evidence: [evidence],
            findings: [CreatorQualityArea.audio, .rightsAndPolicy, .renderIntegrity].map { area in
                QualityFinding(area: area, severity: area == .audio && audioBlocked ? .blocker : .info,
                    title: "Fixture", explanation: "Fixture", recommendedAction: nil, evidenceIDs: [evidence.id])
            }, reviewedAt: Date())
        return (base, PublishPackage(projectID: projectID, targetChannelID: "channel", renderArtifactID: UUID(),
            metadata: .init(title: title, description: "", privacyStatus: .privateVideo, selfDeclaredMadeForKids: false),
            thumbnail: nil, captions: []))
    }
}
