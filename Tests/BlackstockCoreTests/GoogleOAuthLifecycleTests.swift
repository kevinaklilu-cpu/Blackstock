import XCTest
@testable import BlackstockCore

final class GoogleOAuthLifecycleTests: XCTestCase {
    func testReadOnlyFirstRunNeedsOnlyReadScope() {
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly],
            tokenScopeString: nil
        )

        XCTAssertEqual(plan.state, .reauthorizationRequired)
        XCTAssertEqual(plan.missingScopes, [.youtubeReadOnly])
        XCTAssertEqual(plan.scopesForAuthorization, [.youtubeReadOnly])
    }

    func testUploadReauthorizationRequestsUnionForInstalledApp() {
        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.discoveryReadOnly, .upload],
            tokenScopeString: GoogleOAuthScope.youtubeReadOnly.rawValue
        )

        XCTAssertEqual(plan.state, .reauthorizationRequired)
        XCTAssertEqual(plan.missingScopes, [.youtubeUpload])
        XCTAssertEqual(
            plan.scopesForAuthorization,
            [.youtubeReadOnly, .youtubeUpload]
        )
    }

    func testAlreadyAuthorizedCapabilityDoesNotRequestMoreScopes() {
        let scopes = [
            GoogleOAuthScope.youtubeReadOnly.rawValue,
            GoogleOAuthScope.analyticsReadOnly.rawValue
        ].joined(separator: " ")

        let plan = GoogleOAuthScopePlanner().plan(
            capabilities: [.analytics],
            tokenScopeString: scopes
        )

        XCTAssertEqual(plan.state, .alreadyAuthorized)
        XCTAssertTrue(plan.missingScopes.isEmpty)
        XCTAssertEqual(
            plan.currentlyGranted,
            [.youtubeReadOnly, .analyticsReadOnly]
        )
    }

    func testRevenueAnalyticsHasSeparateMonetaryScope() {
        XCTAssertEqual(
            GoogleOAuthCapability.revenueAnalytics.requiredScopes,
            [.analyticsMonetaryReadOnly]
        )
    }

    func testUnknownGrantedScopesAreIgnoredInsteadOfInvented() {
        let parsed = GoogleOAuthScopePlanner.parseGrantedScopes(
            "unknown.scope \(GoogleOAuthScope.youtubeReadOnly.rawValue)"
        )
        XCTAssertEqual(parsed, [.youtubeReadOnly])
    }
}
