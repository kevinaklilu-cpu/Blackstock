import XCTest
import Foundation
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

    func testOAuthJSONParsesDesktopClientSecretForKeychainBackedExchange() throws {
        let data = Data(#"""
        {
          "installed": {
            "client_id": "abc.apps.googleusercontent.com",
            "client_secret": "must-not-be-retained",
            "project_id": "project-123",
            "redirect_uris": ["http://localhost"]
          }
        }
        """#.utf8)

        let config =
            try OAuthClientConfiguration
                .parseGoogleDesktopJSON(data)

        XCTAssertEqual(
            config.clientID,
            "abc.apps.googleusercontent.com"
        )
        XCTAssertEqual(config.projectID, "project-123")
        XCTAssertEqual(
            config.redirectURIs,
            ["http://localhost"]
        )

        XCTAssertEqual(
            config.clientSecret,
            "must-not-be-retained"
        )
    }


    func testTokenExchangeSendsDesktopSecretPKCEAndRedirect() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = String(
                data: request.httpBody ?? Data(),
                encoding: .utf8
            ) ?? ""
            XCTAssertTrue(body.contains("client_id=abc.apps.googleusercontent.com"))
            XCTAssertTrue(body.contains("client_secret=desktop-secret"))
            XCTAssertTrue(body.contains("code=auth-code"))
            XCTAssertTrue(body.contains("code_verifier=pkce-verifier"))
            XCTAssertTrue(body.contains("redirect_uri=http%3A%2F%2F127%2E0%2E0%2E1%3A54321"))
            XCTAssertTrue(body.contains("grant_type=authorization_code"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(#"""
            {
              "access_token": "access",
              "refresh_token": "refresh",
              "expires_in": 3600,
              "token_type": "Bearer",
              "scope": "https://www.googleapis.com/auth/youtube.readonly"
            }
            """#.utf8)
            return (response, data)
        }

        let tokens = try await GoogleOAuthTokenExchange().exchange(
            code: "auth-code",
            clientID: "abc.apps.googleusercontent.com",
            clientSecret: "desktop-secret",
            redirectURI: URL(string: "http://127.0.0.1:54321")!,
            verifier: "pkce-verifier",
            session: session
        )

        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(tokens.refreshToken, "refresh")
    }

    func testTokenExchangeSurfacesGoogle400Details() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(#"""
            {
              "error": "invalid_grant",
              "error_description": "Bad Request"
            }
            """#.utf8)
            return (response, data)
        }

        do {
            _ = try await GoogleOAuthTokenExchange().exchange(
                code: "bad-code",
                clientID: "abc.apps.googleusercontent.com",
                clientSecret: "desktop-secret",
                redirectURI: URL(string: "http://127.0.0.1:54321")!,
                verifier: "pkce-verifier",
                session: session
            )
            XCTFail("Expected token exchange failure")
        } catch let error as GoogleOAuthError {
            XCTAssertEqual(
                error,
                .tokenExchangeFailed(
                    400,
                    "invalid_grant",
                    "Bad Request"
                )
            )
            XCTAssertTrue(
                error.localizedDescription.contains("invalid_grant")
            )
        }
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


private final class OAuthURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "oauth2.googleapis.com"
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "OAuthURLProtocol",
                    code: 1
                )
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
