import XCTest
@testable import BlackstockCore

final class CanonicalTests: XCTestCase {
    func testCapabilityHiddenUntilEveryGatePasses() async {
        let r = CapabilityRecord(
            capabilityId: "youtube.upload",
            provider: "YouTube",
            implementationVersion: "1",
            authorizationState: .authorized,
            policyState: .allowed,
            regionAvailability: .available,
            channelAvailability: .available,
            requiredScopes: [GoogleOAuthScope.youtubeUpload.rawValue],
            dataAvailability: .available,
            qualityStatus: .pass,
            testStatus: .fail,
            lastVerifiedAt: Date()
        )
        let registry = CapabilityRegistry(records: [r])
        let visible = await registry.isVisible(
            "youtube.upload",
            grantedScopes: [GoogleOAuthScope.youtubeUpload.rawValue]
        )
        XCTAssertFalse(visible)
    }

    func testCapabilityHiddenWhenRequiredScopeIsMissing() async {
        let record = CapabilityRecord(
            capabilityId: "youtube.upload",
            provider: "YouTube",
            implementationVersion: "1",
            authorizationState: .authorized,
            policyState: .allowed,
            regionAvailability: .available,
            channelAvailability: .available,
            requiredScopes: [GoogleOAuthScope.youtubeUpload.rawValue],
            dataAvailability: .available,
            qualityStatus: .pass,
            testStatus: .pass,
            lastVerifiedAt: Date()
        )
        let registry = CapabilityRegistry(records: [record])
        XCTAssertFalse(await registry.isVisible("youtube.upload", grantedScopes: []))
        XCTAssertTrue(await registry.isVisible(
            "youtube.upload",
            grantedScopes: [GoogleOAuthScope.youtubeUpload.rawValue]
        ))
    }

    func testWrongChannelHardStops() {
        let c = PublicationPreflightContext(projectTargetChannelID: "A", workspaceChannelID: "B", authorizedUploadChannelID: "A", renderValidated: true, rightsValidated: true, authorizationAvailable: true, quotaAvailable: true, networkAvailable: true)
        XCTAssertThrowsError(try c.validate()) { XCTAssertEqual($0 as? PublicationPreflightError, .wrongChannel) }
    }

    func testRemoteHighImpactRequiresConfirmation() {
        XCTAssertFalse(ActionAuthorization(riskClass: .remoteHighImpact, deterministicChecksPassed: true, userConfirmed: false).mayExecute)
    }

    func testOAuthDesktopJSONImport() throws {
        let valid = Data(#"{"installed":{"client_id":"abc.apps.googleusercontent.com","client_secret":"ignored"}}"#.utf8)
        XCTAssertEqual(try OAuthClientConfiguration.parseGoogleDesktopJSON(valid).clientID, "abc.apps.googleusercontent.com")
        let web = Data(#"{"web":{"client_id":"abc.apps.googleusercontent.com"}}"#.utf8)
        XCTAssertThrowsError(try OAuthClientConfiguration.parseGoogleDesktopJSON(web))
    }

    func testTemporalSemanticsAreDistinct() {
        XCTAssertNotEqual(TemporalSemantic.publishedInWindow, .observedInWindow)
        XCTAssertNotEqual(TemporalSemantic.publishedInWindow, .externalTrendPeriod)
    }
}