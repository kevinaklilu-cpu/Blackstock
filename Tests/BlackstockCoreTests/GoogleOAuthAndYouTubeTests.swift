import XCTest
@testable import BlackstockCore

final class GoogleOAuthAndYouTubeTests: XCTestCase {
    func testPKCEUsesS256AndURLSafeValues() throws {
        let pair = try PKCEPair.generate()
        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertFalse(pair.verifier.contains("="))
        XCTAssertFalse(pair.challenge.contains("="))
        XCTAssertFalse(pair.challenge.contains("+"))
        XCTAssertFalse(pair.challenge.contains("/"))
    }

    func testAuthorizationRequestContainsDesktopPKCEAndLeastPrivilegeScope() throws {
        let pair = try PKCEPair.generate()
        let request = GoogleOAuthAuthorizationRequest(
            clientID: "abc.apps.googleusercontent.com",
            redirectURI: URL(string: "http://127.0.0.1:54321")!,
            scopes: [.youtubeReadOnly],
            state: "state-123",
            pkce: pair
        )
        let components = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)!
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.host, "accounts.google.com")
        XCTAssertEqual(values["response_type"], "code")
        XCTAssertEqual(
            values["redirect_uri"],
            "http://127.0.0.1:54321"
        )
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertEqual(values["state"], "state-123")
        XCTAssertEqual(values["scope"], GoogleOAuthScope.youtubeReadOnly.rawValue)
        XCTAssertFalse(values["scope"]?.contains(GoogleOAuthScope.youtubeUpload.rawValue) == true)
    }

    func testOAuthJSONRequiresDesktopInstalledClient() throws {
        let desktop = Data(#"""
        {"installed":{"client_id":"abc.apps.googleusercontent.com","client_secret":"ignored","redirect_uris":["http://localhost"]}}
        """#.utf8)
        let config = try OAuthClientConfiguration.parseGoogleDesktopJSON(desktop)
        XCTAssertEqual(config.clientID, "abc.apps.googleusercontent.com")

        let web = Data(#"""
        {"web":{"client_id":"abc.apps.googleusercontent.com","client_secret":"secret"}}
        """#.utf8)
        XCTAssertThrowsError(try OAuthClientConfiguration.parseGoogleDesktopJSON(web)) {
            XCTAssertEqual($0 as? OAuthClientConfigurationError, .unsupportedClientType)
        }
    }

    func testOAuthJSONRejectsMissingAndInvalidClientIDs() throws {
        let missing = Data(#"""
        {"installed":{"client_id":"   ","redirect_uris":["http://localhost"]}}
        """#.utf8)
        XCTAssertThrowsError(
            try OAuthClientConfiguration.parseGoogleDesktopJSON(
                missing
            )
        ) {
            XCTAssertEqual(
                $0 as? OAuthClientConfigurationError,
                .missingClientID
            )
        }

        let invalid = Data(#"""
        {"installed":{"client_id":"not-a-google-client","redirect_uris":["http://localhost"]}}
        """#.utf8)
        XCTAssertThrowsError(
            try OAuthClientConfiguration.parseGoogleDesktopJSON(
                invalid
            )
        ) {
            XCTAssertEqual(
                $0 as? OAuthClientConfigurationError,
                .invalidClientID
            )
        }
    }

    func testOAuthJSONParsesDesktopClientSecretForTokenExchange() throws {
        let data = Data(#"""
        {
          "installed": {
            "client_id": "abc.apps.googleusercontent.com",
            "client_secret": "desktop-client-secret",
            "project_id": "project-123",
            "redirect_uris": ["http://localhost"]
          }
        }
        """#.utf8)

        let config = try OAuthClientConfiguration
            .parseGoogleDesktopJSON(data)

        XCTAssertEqual(
            config.clientID,
            "abc.apps.googleusercontent.com"
        )
        XCTAssertEqual(
            config.clientSecret,
            "desktop-client-secret"
        )
        XCTAssertEqual(config.projectID, "project-123")
        XCTAssertEqual(
            config.redirectURIs,
            ["http://localhost"]
        )
    }

    func testOAuthFormEncodingKeepsPKCEAndRedirectValuesValid() {
        let body = oauthFormBody([
            "code_verifier": "a_b-c.d~e",
            "redirect_uri": "http://127.0.0.1:54321"
        ])
        let text = String(data: body ?? Data(), encoding: .utf8)

        XCTAssertTrue(
            text?.contains("code_verifier=a_b-c.d~e") == true
        )
        XCTAssertTrue(
            text?.contains(
                "redirect_uri=http%3A%2F%2F127.0.0.1%3A54321"
            ) == true
        )
    }

    func testImportedOAuthClientIDOverridesBundledConfiguration() {
        XCTAssertEqual(
            OAuthClientConfiguration.preferredClientID(
                bundled: "bundled.apps.googleusercontent.com",
                imported: " imported.apps.googleusercontent.com "
            ),
            "imported.apps.googleusercontent.com"
        )
        XCTAssertEqual(
            OAuthClientConfiguration.preferredClientID(
                bundled: " bundled.apps.googleusercontent.com ",
                imported: "  "
            ),
            "bundled.apps.googleusercontent.com"
        )
    }

    func testActionBrokerStillRequiresConfirmationForRemoteHighImpact() {
        XCTAssertFalse(
            ActionAuthorization(
                riskClass: .remoteHighImpact,
                deterministicChecksPassed: true,
                userConfirmed: false
            ).mayExecute
        )
    }
}
