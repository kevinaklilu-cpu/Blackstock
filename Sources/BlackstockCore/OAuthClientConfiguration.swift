import Foundation

public enum OAuthClientConfigurationError: Error, Equatable, Sendable { case invalidJSON, unsupportedClientType, missingClientID, invalidClientID }

public struct OAuthClientConfiguration: Sendable, Equatable {
    public let clientID: String
    public let projectID: String?
    public let redirectURIs: [String]
    public static func parseGoogleDesktopJSON(_ data: Data) throws -> OAuthClientConfiguration {
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) } catch { throw OAuthClientConfigurationError.invalidJSON }
        guard let installed = envelope.installed else { throw OAuthClientConfigurationError.unsupportedClientType }
        let id = installed.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw OAuthClientConfigurationError.missingClientID }
        guard id.hasSuffix(".apps.googleusercontent.com") else { throw OAuthClientConfigurationError.invalidClientID }
        return OAuthClientConfiguration(clientID: id, projectID: installed.projectID, redirectURIs: installed.redirectURIs ?? [])
    }

    public static func preferredClientID(bundled: String, imported: String) -> String {
        let importedValue = imported.trimmingCharacters(in: .whitespacesAndNewlines)
        if !importedValue.isEmpty { return importedValue }
        return bundled.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct Envelope: Decodable { let installed: Installed? }
private struct Installed: Decodable {
    let clientID: String
    let projectID: String?
    let redirectURIs: [String]?
    enum CodingKeys: String, CodingKey { case clientID = "client_id"; case projectID = "project_id"; case redirectURIs = "redirect_uris" }
}