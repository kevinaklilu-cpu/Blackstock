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
        let quality = completeQualityReview(
            projectID: projectID,
            evidence: evidence
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

    func testProductionStageCannotPublishDirectly() {
        let projectID = UUID()
        let project = BlackstockProject(
            id: projectID,
            title: "Video",
            targetChannelID: "channel-A",
            stage: .production,
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
                .projectStageNotReady
            )
        }
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

    func testUnreadableThumbnailBlocksPublishReview() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("not-an-image".utf8).write(to: source)

        let setup = makeReview(
            privacy: .privateVideo,
            publicPublishingAllowed: false,
            userConfirmed: true,
            thumbnail: PublishThumbnail(
                fileURL: source,
                mimeType: "image/png"
            )
        )

        XCTAssertThrowsError(try setup.validate()) {
            XCTAssertEqual(
                $0 as? PublishPackageValidationError,
                .thumbnailInvalid
            )
        }
    }

    func testEmptyCaptionFileBlocksPublishReview() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vtt")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data().write(to: source)

        let setup = makeReview(
            privacy: .privateVideo,
            publicPublishingAllowed: false,
            userConfirmed: true,
            captions: [
                PublishCaptionTrack(
                    language: "de",
                    name: "Deutsch",
                    fileURL: source,
                    mimeType: "text/vtt"
                )
            ]
        )

        XCTAssertThrowsError(try setup.validate()) {
            XCTAssertEqual(
                $0 as? PublishPackageValidationError,
                .captionInvalid
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

    private func completeQualityReview(
        projectID: UUID,
        evidence: QualityEvidence
    ) -> CreatorQualityReview {
        let required: [CreatorQualityArea] = [
            .packaging,
            .retentionStructure,
            .audio,
            .captions,
            .visualComposition,
            .rightsAndPolicy,
            .renderIntegrity
        ]
        return CreatorQualityReview(
            projectID: projectID,
            stage: .review,
            evidence: [evidence],
            findings: required.map { area in
                QualityFinding(
                    area: area,
                    severity: .info,
                    title: "\(area.rawValue) geprüft",
                    explanation: "Test-Evidenz liegt vor.",
                    recommendedAction: nil,
                    evidenceIDs: [evidence.id]
                )
            },
            reviewedAt: Date()
        )
    }

    private func makeReview(
        privacy: YouTubePrivacyStatus,
        publicPublishingAllowed: Bool,
        userConfirmed: Bool,
        thumbnail: PublishThumbnail? = nil,
        captions: [PublishCaptionTrack] = []
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
        let quality = completeQualityReview(
            projectID: projectID,
            evidence: evidence
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
            thumbnail: thumbnail,
            captions: captions
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
