import XCTest
import Foundation
@testable import BlackstockCore

final class GoogleOAuthAndYouTubeTests: XCTestCase {
    func testDiscoveryPaginationPreservesFiltersAndSortsNumericViews() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { OAuthURLProtocol.handler = nil; session.invalidateAndCancel() }
        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let values = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            let json: String
            if url.path.hasSuffix("/search") {
                XCTAssertEqual(values["maxResults"], "50")
                XCTAssertEqual(values["pageToken"], "page-two")
                XCTAssertEqual(values["order"], "viewCount")
                XCTAssertEqual(values["regionCode"], "DE")
                XCTAssertEqual(values["relevanceLanguage"], "de")
                json = #"{"nextPageToken":"page-three","items":[{"id":{"videoId":"low"},"snippet":{"title":"Low","channelId":"c","channelTitle":"Channel"}},{"id":{"videoId":"high"},"snippet":{"title":"High","channelId":"c","channelTitle":"Channel"}}]}"#
            } else {
                json = #"{"items":[{"id":"low","statistics":{"viewCount":"9"},"contentDetails":{"duration":"PT5M"}},{"id":"high","statistics":{"viewCount":"100"},"contentDetails":{"duration":"PT5M"}}]}"#
            }
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let page = try await YouTubeAuthorizedClient(accessToken: "test").opportunityPage(
            query: "football", regionCode: "DE", relevanceLanguage: "de",
            maxResults: 100, order: .views, pageToken: "page-two", session: session)
        XCTAssertEqual(page.candidates.map(\.videoID), ["high", "low"])
        XCTAssertEqual(page.nextPageToken, "page-three")
    }

    func testFilteredEmptyDiscoveryPageRetainsNextPage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { OAuthURLProtocol.handler = nil; session.invalidateAndCancel() }
        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"items":[],"nextPageToken":"more"}"#.utf8))
        }
        let page = try await YouTubeAuthorizedClient(accessToken: "test").opportunityPage(
            query: "football", contentFilter: .shorts, session: session)
        XCTAssertTrue(page.candidates.isEmpty)
        XCTAssertEqual(page.nextPageToken, "more")
    }

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
                data: OAuthURLProtocol.bodyData(from: request),
                encoding: .utf8
            ) ?? ""
            let fields = Dictionary(
                uniqueKeysWithValues: body
                    .split(separator: "&")
                    .compactMap { pair -> (String, String)? in
                        let parts = pair.split(
                            separator: "=",
                            maxSplits: 1,
                            omittingEmptySubsequences: false
                        )
                        guard parts.count == 2 else { return nil }
                        let key = String(parts[0])
                            .removingPercentEncoding
                            ?? String(parts[0])
                        let value = String(parts[1])
                            .removingPercentEncoding
                            ?? String(parts[1])
                        return (key, value)
                    }
            )
            XCTAssertEqual(
                fields["client_id"],
                "abc.apps.googleusercontent.com"
            )
            XCTAssertEqual(
                fields["client_secret"],
                "desktop-secret"
            )
            XCTAssertEqual(fields["code"], "auth-code")
            XCTAssertEqual(
                fields["code_verifier"],
                "pkce-verifier"
            )
            XCTAssertEqual(
                fields["redirect_uri"],
                "http://127.0.0.1:54321"
            )
            XCTAssertEqual(
                fields["grant_type"],
                "authorization_code"
            )

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

    func testYouTubeSetupCatalogsUseProviderParameters() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )

            let json: String
            switch url.path {
            case "/youtube/v3/i18nLanguages":
                XCTAssertEqual(values["part"], "snippet")
                XCTAssertEqual(values["hl"], "de")
                json = #"""
                {"items":[{"id":"de","snippet":{"hl":"de","name":"Deutsch"}}]}
                """#
            case "/youtube/v3/i18nRegions":
                XCTAssertEqual(values["part"], "snippet")
                XCTAssertEqual(values["hl"], "de")
                json = #"""
                {"items":[{"id":"DE","snippet":{"gl":"DE","name":"Deutschland"}}]}
                """#
            case "/youtube/v3/videoCategories":
                XCTAssertEqual(values["part"], "snippet")
                XCTAssertEqual(values["regionCode"], "DE")
                XCTAssertEqual(values["hl"], "de")
                json = #"""
                {"items":[{"id":"28","snippet":{"title":"Wissenschaft & Technik","assignable":true}}]}
                """#
            default:
                XCTFail("Unexpected YouTube path: \(url.path)")
                json = #"{"items":[]}"#
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            return (response, Data(json.utf8))
        }

        let client = YouTubeChannelSetupClient(
            accessToken: "access"
        )
        let languages = try await client.supportedLanguages(
            displayLanguage: "de",
            session: session
        )
        let regions = try await client.supportedRegions(
            displayLanguage: "de",
            session: session
        )
        let categories = try await client.videoCategories(
            regionCode: "DE",
            languageCode: "de",
            session: session
        )

        XCTAssertEqual(languages.first?.code, "de")
        XCTAssertEqual(regions.first?.code, "DE")
        XCTAssertEqual(categories.first?.id, "28")
        XCTAssertEqual(
            categories.first?.title,
            "Wissenschaft & Technik"
        )
    }

    func testChannelBrandingUpdatePreservesExistingProviderFields() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )

            if request.httpMethod == "GET" {
                XCTAssertEqual(
                    values["part"],
                    "brandingSettings,status"
                )
                XCTAssertEqual(
                    values["id"],
                    "channel-1"
                )
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json"
                    ]
                )!
                let data = Data(#"""
                {
                  "items": [{
                    "id": "channel-1",
                    "brandingSettings": {
                      "channel": {
                        "description": "Keep description",
                        "keywords": "alpha beta",
                        "defaultLanguage": "en",
                        "country": "US",
                        "trackingAnalyticsAccountId": "UA-1",
                        "unsubscribedTrailer": "video-1"
                      }
                    },
                    "status": {
                      "madeForKids": false,
                      "selfDeclaredMadeForKids": false
                    }
                  }]
                }
                """#.utf8)
                return (response, data)
            }

            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(
                values["part"],
                "brandingSettings"
            )
            let body = try JSONSerialization.jsonObject(
                with: OAuthURLProtocol.bodyData(from: request)
            ) as? [String: Any]
            XCTAssertEqual(
                body?["id"] as? String,
                "channel-1"
            )
            let branding = body?["brandingSettings"]
                as? [String: Any]
            let channel = branding?["channel"]
                as? [String: Any]
            XCTAssertEqual(
                channel?["country"] as? String,
                "DE"
            )
            XCTAssertEqual(
                channel?["defaultLanguage"] as? String,
                "de"
            )
            XCTAssertEqual(
                channel?["description"] as? String,
                "Keep description"
            )
            XCTAssertEqual(
                channel?["keywords"] as? String,
                "alpha beta"
            )
            XCTAssertEqual(
                channel?["trackingAnalyticsAccountId"]
                    as? String,
                "UA-1"
            )
            XCTAssertEqual(
                channel?["unsubscribedTrailer"] as? String,
                "video-1"
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            return (response, Data(#"{"id":"channel-1"}"#.utf8))
        }

        let client = YouTubeChannelSetupClient(
            accessToken: "access"
        )
        let snapshot = try await client.currentChannelSetup(
            channelID: "channel-1",
            session: session
        )
        try await client.updateBranding(
            snapshot: snapshot,
            countryCode: "DE",
            defaultLanguage: "de",
            session: session
        )
    }

    func testChannelAudienceUpdateSendsOfficialMadeForKidsFlag() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(values["part"], "status")

            let body = try JSONSerialization.jsonObject(
                with: OAuthURLProtocol.bodyData(from: request)
            ) as? [String: Any]
            let status = body?["status"] as? [String: Any]
            XCTAssertEqual(
                status?["selfDeclaredMadeForKids"] as? Bool,
                true
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            return (response, Data(#"{"id":"channel-1"}"#.utf8))
        }

        try await YouTubeChannelSetupClient(
            accessToken: "access"
        ).updateAudience(
            channelID: "channel-1",
            selfDeclaredMadeForKids: true,
            session: session
        )
    }

    func testChannelSetupDoesNotBlockWhenAudienceWriteIsRejected() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )

            if request.httpMethod == "PUT",
               values["part"] == "status" {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 400,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json"
                    ]
                )!
                let data = Data(#"""
                {"error":{"message":"Unsupported channel audience part"}}
                """#.utf8)
                return (response, data)
            }

            if request.httpMethod == "PUT" {
                XCTAssertEqual(
                    values["part"],
                    "brandingSettings"
                )
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json"
                    ]
                )!
                return (
                    response,
                    Data(#"{"id":"channel-1"}"#.utf8)
                )
            }

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            let data = Data(#"""
            {
              "items": [{
                "id": "channel-1",
                "brandingSettings": {
                  "channel": {
                    "description": "Keep",
                    "keywords": "sports",
                    "defaultLanguage": "de",
                    "country": "DE"
                  }
                },
                "status": {
                  "madeForKids": false
                }
              }]
            }
            """#.utf8)
            return (response, data)
        }

        let result = try await YouTubeChannelSetupClient(
            accessToken: "access"
        ).applyAndVerify(
            channelID: "channel-1",
            countryCode: "DE",
            defaultLanguage: "de",
            audience: .madeForKids,
            session: session
        )

        XCTAssertEqual(
            result.snapshot.countryCode,
            "DE"
        )
        XCTAssertEqual(
            result.snapshot.defaultLanguage,
            "de"
        )
        XCTAssertEqual(
            result.audienceAppliedToChannel,
            false
        )
        XCTAssertNil(
            YouTubeChannelAudienceSetting.perVideo
                .selfDeclaredMadeForKids
        )
    }

    func testOpportunitySearchUsesStructuredYouTubeFiltersWithoutFreeText() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(
                url.path,
                "/youtube/v3/search"
            )
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )
            XCTAssertNil(values["q"])
            XCTAssertEqual(
                values["videoCategoryId"],
                "28"
            )
            XCTAssertEqual(values["regionCode"], "DE")
            XCTAssertEqual(
                values["relevanceLanguage"],
                "de"
            )
            XCTAssertEqual(
                values["videoEmbeddable"],
                "true"
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            return (
                response,
                Data(#"{"items":[]}"#.utf8)
            )
        }

        let candidates = try await YouTubeAuthorizedClient(
            accessToken: "access"
        ).firstOpportunityCandidates(
            query: "",
            categoryID: "28",
            regionCode: "DE",
            relevanceLanguage: "de",
            session: session
        )
        XCTAssertTrue(candidates.isEmpty)
    }

    func testMostPopularCategoryUsesOfficialVideoChart() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/youtube/v3/videos")
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )
            XCTAssertEqual(values["chart"], "mostPopular")
            XCTAssertEqual(values["regionCode"], "DE")
            XCTAssertEqual(values["videoCategoryId"], "17")
            XCTAssertEqual(
                values["part"],
                "snippet,statistics,status,contentDetails,liveStreamingDetails"
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            let data = Data(#"""
            {
              "items": [{
                "id": "sports-1",
                "snippet": {
                  "publishedAt": "2026-09-20T10:00:00Z",
                  "channelId": "sports-channel",
                  "title": "Sports highlight",
                  "channelTitle": "Sports",
                  "thumbnails": {}
                },
                "statistics": {
                  "viewCount": "12345",
                  "likeCount": "321",
                  "commentCount": "45"
                },
                "status": {
                  "embeddable": true
                }
              }]
            }
            """#.utf8)
            return (response, data)
        }

        let candidates = try await YouTubeAuthorizedClient(
            accessToken: "access"
        ).categoryOpportunityCandidates(
            categoryID: "17",
            categoryTitle: "Sport",
            regionCode: "DE",
            relevanceLanguage: "de",
            timeWindow: .allTime,
            maxResults: 12,
            order: .relevance,
            session: session
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.videoID, "sports-1")
        XCTAssertEqual(
            candidates.first?.metrics.viewCount,
            12_345
        )
    }

    func testPublishedAfterTimeWindowUsesViewCountSearch() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        let session = URLSession(configuration: configuration)

        OAuthURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/youtube/v3/search")
            let components = try XCTUnwrap(
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )
            )
            let values = Dictionary(
                uniqueKeysWithValues:
                    (components.queryItems ?? []).map {
                        ($0.name, $0.value ?? "")
                    }
            )
            XCTAssertEqual(values["order"], "viewCount")
            XCTAssertEqual(values["videoCategoryId"], "17")
            XCTAssertEqual(values["regionCode"], "DE")
            XCTAssertEqual(
                values["publishedAfter"],
                "2026-09-19T12:00:00Z"
            )

            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!
            return (
                response,
                Data(#"{"items":[]}"#.utf8)
            )
        }

        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(
                from: "2026-09-20T12:00:00Z"
            )
        )
        let candidates = try await YouTubeAuthorizedClient(
            accessToken: "access"
        ).firstOpportunityCandidates(
            query: "",
            categoryID: "17",
            regionCode: "DE",
            relevanceLanguage: "de",
            publishedAfter:
                OpportunityTimeWindow.last24Hours
                    .publishedAfter(now: now),
            maxResults: 12,
            order: .views,
            session: session,
            now: now
        )
        XCTAssertTrue(candidates.isEmpty)
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

    static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bufferSize
        )
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(
                buffer,
                maxLength: bufferSize
            )
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else {
            return false
        }
        return host == "oauth2.googleapis.com"
            || host == "www.googleapis.com"
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
