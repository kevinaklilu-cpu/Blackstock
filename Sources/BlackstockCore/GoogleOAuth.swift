import Foundation
import CryptoKit
import Security

public enum GoogleOAuthScope: String, Codable, Sendable, CaseIterable {
    case youtubeReadOnly = "https://www.googleapis.com/auth/youtube.readonly"
    case youtubeUpload = "https://www.googleapis.com/auth/youtube.upload"
    case analyticsReadOnly = "https://www.googleapis.com/auth/yt-analytics.readonly"
}

public struct PKCEPair: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public static func generate() throws -> PKCEPair {
        var bytes = [UInt8](repeating: 0, count: 48)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { throw GoogleOAuthError.randomGenerationFailed }
        let verifier = Data(bytes).base64URLEncodedString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCEPair(verifier: verifier, challenge: challenge)
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
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.map(\.rawValue).sorted().joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "select_account consent")
        ]
        return c.url!
    }
}

public struct GoogleOAuthTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String
    public let scope: String?

    public init(accessToken: String, refreshToken: String?, expiresIn: Int, tokenType: String, scope: String?) {
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

public struct GoogleOAuthTokenExchange: Sendable {
    public init() {}

    public func exchange(
        code: String,
        clientID: String,
        redirectURI: URL,
        verifier: String,
        session: URLSession = .shared
    ) async throws -> GoogleOAuthTokenSet {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        request.httpBody = fields
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key.formURLEncoded)=\(value.formURLEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GoogleOAuthError.tokenExchangeFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(GoogleOAuthTokenSet.self, from: data)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
