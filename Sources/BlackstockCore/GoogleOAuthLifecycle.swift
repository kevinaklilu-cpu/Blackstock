import Foundation

public enum GoogleOAuthCapability: String, Codable, Sendable {
    case discoveryReadOnly
    case upload
    case packaging
    case analytics
    case revenueAnalytics

    public var requiredScopes: Set<GoogleOAuthScope> {
        switch self {
        case .discoveryReadOnly:
            return [.youtubeReadOnly]
        case .upload:
            return [.youtubeUpload]
        case .packaging:
            return [.youtubeForceSSL]
        case .analytics:
            return [.analyticsReadOnly]
        case .revenueAnalytics:
            return [.analyticsMonetaryReadOnly]
        }
    }
}

public enum GoogleOAuthScopePlanState: String, Codable, Sendable {
    case alreadyAuthorized = "ALREADY_AUTHORIZED"
    case reauthorizationRequired = "REAUTHORIZATION_REQUIRED"
}

public struct GoogleOAuthScopePlan: Sendable, Equatable {
    public let state: GoogleOAuthScopePlanState
    public let currentlyGranted: Set<GoogleOAuthScope>
    public let missingScopes: Set<GoogleOAuthScope>
    public let scopesForAuthorization: Set<GoogleOAuthScope>

    public init(
        state: GoogleOAuthScopePlanState,
        currentlyGranted: Set<GoogleOAuthScope>,
        missingScopes: Set<GoogleOAuthScope>,
        scopesForAuthorization: Set<GoogleOAuthScope>
    ) {
        self.state = state
        self.currentlyGranted = currentlyGranted
        self.missingScopes = missingScopes
        self.scopesForAuthorization = scopesForAuthorization
    }
}

public struct GoogleOAuthScopePlanner: Sendable {
    public init() {}

    public func plan(
        capabilities: Set<GoogleOAuthCapability>,
        tokenScopeString: String?
    ) -> GoogleOAuthScopePlan {
        let granted = Self.parseGrantedScopes(tokenScopeString)
        let required = capabilities.reduce(into: Set<GoogleOAuthScope>()) {
            $0.formUnion($1.requiredScopes)
        }
        let missing = required.subtracting(granted)

        if missing.isEmpty {
            return .init(
                state: .alreadyAuthorized,
                currentlyGranted: granted,
                missingScopes: [],
                scopesForAuthorization: granted
            )
        }

        // Installed/desktop apps do not support Google's incremental authorization
        // feature. Re-authorization therefore requests the union explicitly.
        return .init(
            state: .reauthorizationRequired,
            currentlyGranted: granted,
            missingScopes: missing,
            scopesForAuthorization: granted.union(required)
        )
    }

    public static func parseGrantedScopes(_ value: String?) -> Set<GoogleOAuthScope> {
        guard let value else { return [] }
        return Set(
            value
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { GoogleOAuthScope(rawValue: String($0)) }
        )
    }
}

public struct GoogleOAuthTokenRefresher: Sendable {
    public init() {}

    public func refresh(
        refreshToken: String,
        clientID: String,
        clientSecret: String? = nil,
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
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
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

        let refreshed = try JSONDecoder().decode(
            GoogleOAuthTokenSet.self,
            from: data
        )
        return GoogleOAuthTokenSet(
            accessToken: refreshed.accessToken,
            refreshToken: refreshToken,
            expiresIn: refreshed.expiresIn,
            tokenType: refreshed.tokenType,
            scope: refreshed.scope
        )
    }
}
