import Foundation
import CryptoKit
import Security

public enum GoogleOAuthScope: String, Codable, Sendable, CaseIterable {
    case youtubeReadOnly = "https://www.googleapis.com/auth/youtube.readonly"
    case youtubeUpload = "https://www.googleapis.com/auth/youtube.upload"
    case youtubeForceSSL = "https://www.googleapis.com/auth/youtube.force-ssl"
    case analyticsReadOnly = "https://www.googleapis.com/auth/yt-analytics.readonly"
    case analyticsMonetaryReadOnly = "https://www.googleapis.com/auth/yt-analytics-monetary.readonly"
}

public struct PKCEPair: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public static func generate() throws -> PKCEPair {
        var bytes = [UInt8](repeating: 0, count: 48)
        let result = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )
        guard result == errSecSuccess else {
            throw GoogleOAuthError.randomGenerationFailed
        }

        let verifier = Data(bytes).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCEPair(
            verifier: verifier,
            challenge: challenge
        )
    }
}

public struct GoogleOAuthAuthorizationRequest: Sendable, Equatable {
    public let clientID: String
    public let redirectURI: URL
    public let scopes: Set<GoogleOAuthScope>
    public let state: String
    public let pkce: PKCEPair

    public init(
        clientID: String,
        redirectURI: URL,
        scopes: Set<GoogleOAuthScope>,
        state: String,
        pkce: PKCEPair
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.state = state
        self.pkce = pkce
    }

    public var authorizationURL: URL {
        var components = URLComponents(
            string: "https://accounts.google.com/o/oauth2/v2/auth"
        )!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(
                name: "redirect_uri",
                value: redirectURI.absoluteString
            ),
            .init(name: "response_type", value: "code"),
            .init(
                name: "scope",
                value: scopes
                    .map(\.rawValue)
                    .sorted()
                    .joined(separator: " ")
            ),
            .init(
                name: "code_challenge",
                value: pkce.challenge
            ),
            .init(
                name: "code_challenge_method",
                value: "S256"
            ),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "select_account consent")
        ]
        return components.url!
    }
}

public struct GoogleOAuthTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String
    public let scope: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int,
        tokenType: String,
        scope: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

public enum GoogleOAuthError: Error, Equatable, Sendable {
    case randomGenerationFailed
    case invalidAuthorizationResponse
    case stateMismatch
    case tokenExchangeFailed(Int)
}

public struct GoogleOAuthTokenEndpointError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    public let statusCode: Int
    public let providerError: String?
    public let providerDescription: String?

    public init(
        statusCode: Int,
        providerError: String?,
        providerDescription: String?
    ) {
        self.statusCode = statusCode
        self.providerError = providerError
        self.providerDescription = providerDescription
    }

    public var errorDescription: String? {
        switch providerError {
        case "invalid_client":
            return "Google hat den OAuth-Client abgelehnt. Importiere die Desktop-OAuth-JSON erneut und prüfe, dass sie zum Client-Typ „Desktop-App“ gehört."
        case "invalid_grant":
            return "Google konnte den Autorisierungscode nicht einlösen. Starte die Verbindung erneut und verwende dieselbe Desktop-OAuth-Konfiguration für Anmeldung und Token-Austausch."
        case "redirect_uri_mismatch":
            return "Die Google-Weiterleitungsadresse passt nicht zum Desktop-OAuth-Client."
        default:
            let reason = [
                providerError,
                providerDescription
            ]
            .compactMap { value in
                value?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")

            if reason.isEmpty {
                return "Google Token-Austausch fehlgeschlagen (HTTP \(statusCode))."
            }
            return "Google Token-Austausch fehlgeschlagen (HTTP \(statusCode)): \(reason)"
        }
    }
}

public struct GoogleOAuthTokenExchange: Sendable {
    public init() {}

    public func exchange(
        code: String,
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL,
        verifier: String,
        session: URLSession = .shared
    ) async throws -> GoogleOAuthTokenSet {
        var request = URLRequest(
            url: URL(
                string: "https://oauth2.googleapis.com/token"
            )!
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        var fields = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        if let clientSecret = normalizedOAuthField(clientSecret) {
            fields["client_secret"] = clientSecret
        }

        request.httpBody = oauthFormBody(fields)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw tokenEndpointError(
                response: response,
                data: data
            )
        }

        return try JSONDecoder().decode(
            GoogleOAuthTokenSet.self,
            from: data
        )
    }
}

private struct GoogleOAuthTokenErrorBody: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

func oauthFormBody(
    _ fields: [String: String]
) -> Data? {
    fields
        .sorted { $0.key < $1.key }
        .map { key, value in
            "\(key.oauthFormEncoded)=\(value.oauthFormEncoded)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
}

func tokenEndpointError(
    response: URLResponse,
    data: Data
) -> GoogleOAuthTokenEndpointError {
    let statusCode =
        (response as? HTTPURLResponse)?.statusCode ?? -1
    let decoded = try? JSONDecoder().decode(
        GoogleOAuthTokenErrorBody.self,
        from: data
    )
    return GoogleOAuthTokenEndpointError(
        statusCode: statusCode,
        providerError: decoded?.error,
        providerDescription: decoded?.errorDescription
    )
}

func normalizedOAuthField(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let normalized = value.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    return normalized.isEmpty ? nil : normalized
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    var oauthFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(
            withAllowedCharacters: allowed
        )?
        .replacingOccurrences(of: "%20", with: "+")
        ?? self
    }
}
