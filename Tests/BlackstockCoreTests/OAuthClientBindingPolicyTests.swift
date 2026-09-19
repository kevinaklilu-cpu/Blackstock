import XCTest
@testable import BlackstockCore

final class OAuthClientBindingPolicyTests: XCTestCase {
    func testSameNormalizedClientPreservesCredentials() {
        XCTAssertFalse(
            OAuthClientBindingPolicy()
                .requiresCredentialInvalidation(
                    previousClientID:
                        " client.apps.googleusercontent.com ",
                    nextClientID:
                        "client.apps.googleusercontent.com"
                )
        )
    }

    func testChangedClientInvalidatesCredentials() {
        XCTAssertTrue(
            OAuthClientBindingPolicy()
                .requiresCredentialInvalidation(
                    previousClientID:
                        "old.apps.googleusercontent.com",
                    nextClientID:
                        "new.apps.googleusercontent.com"
                )
        )
    }

    func testAddingFirstConfiguredClientInvalidatesLegacyCredentials() {
        XCTAssertTrue(
            OAuthClientBindingPolicy()
                .requiresCredentialInvalidation(
                    previousClientID: "",
                    nextClientID:
                        "new.apps.googleusercontent.com"
                )
        )
    }

    func testRemovingOnlyConfiguredClientInvalidatesCredentials() {
        XCTAssertTrue(
            OAuthClientBindingPolicy()
                .requiresCredentialInvalidation(
                    previousClientID:
                        "old.apps.googleusercontent.com",
                    nextClientID: ""
                )
        )
    }
}
