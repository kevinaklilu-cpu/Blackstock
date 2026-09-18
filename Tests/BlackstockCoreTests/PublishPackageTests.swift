import XCTest
@testable import BlackstockCore

final class PublishPackageTests: XCTestCase {
    func testValidPrivatePublishPackagePassesDeterministicReview() throws {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .review,
            strategyVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let evidence = QualityEvidence(
            source: "Render-QA",
            observedFact: "Render ist lesbar.",
            reference: artifact.id.uuidString,
            observedAt: Date()
        )
        let quality = CreatorQualityReview(
            projectID: projectID,
            stage: .review,
            evidence: [evidence],
            findings: [
                .init(
                    area: .renderIntegrity,
                    severity: .info,
                    title: "Render geprüft",
                    explanation: "Render-Artefakt wurde geprüft.",
                    recommendedAction: nil,
                    evidenceIDs: [evidence.id]
                )
            ],
            reviewedAt: Date()
        )
        let package = PublishPackage(
            projectID: projectID,
            targetChannelID: "channel-A",
            renderArtifactID: artifact.id,
            metadata: .init(
                title: "Mein Video",
                description: "",
                privacyStatus: .privateVideo,
                selfDeclaredMadeForKids: false
            ),
            thumbnail: nil,
            captions: []
        )

        let review = PublishReviewContext(
            project: project,
            artifact: artifact,
            package: package,
            qualityReview: quality,
            rightsValidated: true,
            publicPublishingAllowed: false,
            userConfirmed: true
        )

        XCTAssertNoThrow(try review.validate())
    }

    func testPublicPublishRequiresProviderComplianceGate() {
        let setup = makeReview(
            privacy: .publicVideo,
            publicPublishingAllowed: false,
            userConfirmed: true
        )
        XCTAssertThrowsError(try setup.validate()) {
            XCTAssertEqual(
                $0 as? PublishPackageValidationError,
                .publicPublishingNotAllowed
            )
        }
    }

    func testRemotePublishRequiresExplicitUserConfirmation() {
        let setup = makeReview(
            privacy: .privateVideo,
            publicPublishingAllowed: false,
            userConfirmed: false
        )
        XCTAssertThrowsError(try setup.validate()) {
            XCTAssertEqual(
                $0 as? PublishPackageValidationError,
                .userConfirmationRequired
            )
        }
    }

    func testQualityReviewIsMandatory() {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .review,
            strategyVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let package = PublishPackage(
            projectID: projectID,
            targetChannelID: "channel-A",
            renderArtifactID: artifact.id,
            metadata: .init(
                title: "Video",
                description: "",
                privacyStatus: .privateVideo,
                selfDeclaredMadeForKids: false
            ),
            thumbnail: nil,
            captions: []
        )
        let review = PublishReviewContext(
            project: project,
            artifact: artifact,
            package: package,
            qualityReview: nil,
            rightsValidated: true,
            publicPublishingAllowed: false,
            userConfirmed: true
        )

        XCTAssertThrowsError(try review.validate()) {
            XCTAssertEqual(
                $0 as? PublishPackageValidationError,
                .qualityReviewMissing
            )
        }
    }

    private func makeReview(
        privacy: YouTubePrivacyStatus,
        publicPublishingAllowed: Bool,
        userConfirmed: Bool
    ) -> PublishReviewContext {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .review,
            strategyVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        let artifact = RenderArtifact(
            projectID: projectID,
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            sha256: "abc",
            mimeType: "video/mp4",
            validated: true,
            createdAt: Date()
        )
        let evidence = QualityEvidence(
            source: "Render-QA",
            observedFact: "Render validiert.",
            reference: artifact.id.uuidString,
            observedAt: Date()
        )
        let quality = CreatorQualityReview(
            projectID: projectID,
            stage: .review,
            evidence: [evidence],
            findings: [
                .init(
                    area: .renderIntegrity,
                    severity: .info,
                    title: "Render validiert",
                    explanation: "Technische Prüfung bestanden.",
                    recommendedAction: nil,
                    evidenceIDs: [evidence.id]
                )
            ],
            reviewedAt: Date()
        )
        let package = PublishPackage(
            projectID: projectID,
            targetChannelID: "channel-A",
            renderArtifactID: artifact.id,
            metadata: .init(
                title: "Video",
                description: "",
                privacyStatus: privacy,
                selfDeclaredMadeForKids: false
            ),
            thumbnail: nil,
            captions: []
        )
        return .init(
            project: project,
            artifact: artifact,
            package: package,
            qualityReview: quality,
            rightsValidated: true,
            publicPublishingAllowed: publicPublishingAllowed,
            userConfirmed: userConfirmed
        )
    }
}
