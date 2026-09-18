import XCTest
@testable import BlackstockCore

final class CanonicalTests: XCTestCase {
    func testCapabilityHiddenUntilEveryGatePasses() async {
        let r = CapabilityRecord(capabilityID: "youtube.upload", provider: "YouTube", implementationVersion: "1", authorization: .authorized, policy: .allowed, region: .available, channel: .available, data: .available, quality: .pass, tests: .fail, lastVerifiedAt: Date())
        let registry = CapabilityRegistry(records: [r])
        let visible = await registry.isVisible("youtube.upload")
        XCTAssertFalse(visible)
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