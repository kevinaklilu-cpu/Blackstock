#if os(macOS)
import Foundation

enum YouTubeAccessTokenError: LocalizedError {
    case notAuthenticated
    case missingClientID
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Dieser YouTube-Kanal ist nicht mehr angemeldet."
        case .missingClientID: return "Für die YouTube-Anmeldung fehlt die Google OAuth Client-ID."
        case .refreshFailed(let message): return message
        }
    }
}

extension GoogleYouTubeAuth {
    func accessToken(for channelID: String) async throws -> String {
        let refreshToken = Keychain.read("youtube-refresh-\(channelID)").trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedAccessToken = Keychain.read("youtube-access-\(channelID)").trimmingCharacters(in: .whitespacesAndNewlines)

        if refreshToken.isEmpty {
            guard !cachedAccessToken.isEmpty else { throw YouTubeAccessTokenError.notAuthenticated }
            return cachedAccessToken
        }

        let clientID = Self.configuredClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            if !cachedAccessToken.isEmpty { return cachedAccessToken }
            throw YouTubeAccessTokenError.missingClientID
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.blackstockFormEncoded([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(RefreshErrorEnvelope.self, from: data).error_description)
                ?? "YouTube konnte die Anmeldung nicht erneuern. Bitte verbinde den Kanal erneut."
            throw YouTubeAccessTokenError.refreshFailed(message)
        }

        let token = try JSONDecoder().decode(RefreshTokenResponse.self, from: data).accessToken
        Keychain.write(token, account: "youtube-access-\(channelID)")
        return token
    }

    fileprivate static func blackstockFormEncoded(_ values: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return values.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

private struct RefreshTokenResponse: Decodable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

private struct RefreshErrorEnvelope: Decodable {
    let error: String?
    let error_description: String?
}
#endif
