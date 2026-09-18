import XCTest
@testable import BlackstockCore

final class OAuthClientConfigurationTests: XCTestCase {
    func testParsesDesktopOAuthJSONWithoutExposingClientSecret() throws {
        let json = """
        {
          "installed": {
            "client_id": "123-example.apps.googleusercontent.com",
            "project_id": "blackstock-test",
            "client_secret": "must-not-be-used",
            "redirect_uris": ["http://localhost"]
          }
        }
        """
        let config = try OAuthClientConfiguration.parseGoogleDesktopJSON(Data(json.utf8))
        XCTAssertEqual(config.clientID, "123-example.apps.googleusercontent.com")
        XCTAssertEqual(config.projectID, "blackstock-test")
        XCTAssertEqual(config.redirectURIs, ["http://localhost"])
    }

    func testRejectsWebOAuthJSONForDesktopPKCEFlow() {
        let json = """
        {
          "web": {
            "client_id": "123-example.apps.googleusercontent.com",
            "client_secret": "secret"
          }
        }
        """
        XCTAssertThrowsError(try OAuthClientConfiguration.parseGoogleDesktopJSON(Data(json.utf8))) { error in
            XCTAssertEqual(error as? OAuthClientConfigurationError, .unsupportedClientType)
        }
    }

    func testRejectsInvalidClientID() {
        let json = """
        {
          "installed": {
            "client_id": "not-a-google-client"
          }
        }
        """
        XCTAssertThrowsError(try OAuthClientConfiguration.parseGoogleDesktopJSON(Data(json.utf8))) { error in
            XCTAssertEqual(error as? OAuthClientConfigurationError, .invalidClientID)
        }
    }
}
