import XCTest
@testable import BlackstockCore

final class WorkspaceRightsAttestationTests: XCTestCase {
    func testWorkspaceDeclarationAllowsUserDirectedProduction() {
        let attestation = WorkspaceRightsAttestation(
            channelID: "channel-123",
            confirmedByUser: true,
            attestedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertTrue(attestation.permitsUserDirectedProduction)

        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(
                string: "https://www.youtube.com/watch?v=abc123"
            )!,
            externalID: "abc123",
            discoveredAt: Date(timeIntervalSince1970: 2)
        )
        let asset = ProductionMediaAsset(
            displayName: "source.mp4",
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            durationSeconds: 42,
            authorization: .userDeclaredResponsibility,
            rightsEvidence: [
                "Workspace-Nutzererklärung",
                "Automatisch gebunden an youtube: abc123"
            ],
            rightsAttestation: RightsAttestation(
                confirmedByUser: true,
                attestedAt: Date(timeIntervalSince1970: 3)
            ),
            originSource: source,
            importedAt: Date(timeIntervalSince1970: 4)
        )

        XCTAssertTrue(asset.mayEnterProduction)
        XCTAssertEqual(asset.originSource, source)
    }

    func testMissingUserConfirmationBlocksProduction() {
        let asset = ProductionMediaAsset(
            displayName: "source.mp4",
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            durationSeconds: 42,
            authorization: .userDeclaredResponsibility,
            rightsEvidence: ["Workspace-Erklärung"],
            rightsAttestation: RightsAttestation(
                confirmedByUser: false,
                attestedAt: Date()
            ),
            importedAt: Date()
        )

        XCTAssertFalse(asset.mayEnterProduction)
    }

    func testOriginSourceSurvivesCodableRoundTrip() throws {
        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(
                string: "https://www.youtube.com/watch?v=xyz"
            )!,
            externalID: "xyz",
            discoveredAt: Date(timeIntervalSince1970: 5)
        )
        let asset = ProductionMediaAsset(
            displayName: "clip.mp4",
            sourceURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            durationSeconds: 10,
            authorization: .userDeclaredResponsibility,
            rightsEvidence: ["Workspace-Erklärung"],
            rightsAttestation: RightsAttestation(
                confirmedByUser: true,
                attestedAt: Date(timeIntervalSince1970: 6)
            ),
            originSource: source,
            importedAt: Date(timeIntervalSince1970: 7)
        )

        let encoded = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(
            ProductionMediaAsset.self,
            from: encoded
        )

        XCTAssertEqual(decoded.originSource, source)
        XCTAssertTrue(decoded.mayEnterProduction)
    }
}
