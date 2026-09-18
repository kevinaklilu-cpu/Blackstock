import Foundation

public enum OAuthClientConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case unsupportedClientType
    case missingClientID
    case invalidClientID

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Die OAuth-JSON-Datei ist nicht gültig."
        case .unsupportedClientType:
            return "Blackstock unterstützt für den lokalen PKCE-Flow nur eine Google-OAuth-Konfiguration vom Typ Desktopanwendung."
        case .missingClientID:
            return "Die OAuth-JSON-Datei enthält keine Client-ID."
        case .invalidClientID:
            return "Die OAuth-JSON-Datei enthält keine gültige Google-Client-ID."
        }
    }
}

public struct OAuthClientConfiguration: Sendable, Equatable {
    public let clientID: String
    public let projectID: String?
    public let redirectURIs: [String]

    public init(clientID: String, projectID: String?, redirectURIs: [String]) {
        self.clientID = clientID
        self.projectID = projectID
        self.redirectURIs = redirectURIs
    }

    public static func parseGoogleDesktopJSON(_ data: Data) throws -> OAuthClientConfiguration {
        let envelope: GoogleOAuthEnvelope
        do {
            envelope = try JSONDecoder().decode(GoogleOAuthEnvelope.self, from: data)
        } catch {
            throw OAuthClientConfigurationError.invalidJSON
        }

        guard let installed = envelope.installed else {
            throw OAuthClientConfigurationError.unsupportedClientType
        }

        let clientID = installed.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw OAuthClientConfigurationError.missingClientID
        }
        guard clientID.hasSuffix(".apps.googleusercontent.com") else {
            throw OAuthClientConfigurationError.invalidClientID
        }

        return OAuthClientConfiguration(
            clientID: clientID,
            projectID: installed.projectID,
            redirectURIs: installed.redirectURIs ?? []
        )
    }
}

private struct GoogleOAuthEnvelope: Decodable {
    let installed: GoogleInstalledOAuthClient?
    // Intentionally do not decode or expose "web".
}

private struct GoogleInstalledOAuthClient: Decodable {
    let clientID: String
    let projectID: String?
    let redirectURIs: [String]?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case projectID = "project_id"
        case redirectURIs = "redirect_uris"
    }
}
