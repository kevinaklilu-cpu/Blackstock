import Foundation

public enum YouTubePackagingError: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    case invalidFile
    case api(Int)
    case missingVideoID
    case rejected(Int, String)

    public var errorDescription: String? {
        switch self {
        case .api(403), .rejected(403, _):
            let reason: String
            if case .rejected(_, let value) = self { reason = value } else { reason = "forbidden" }
            if reason == "quotaExceeded" || reason == "dailyLimitExceeded" {
                return "YouTubes API-Kontingent ist ausgeschöpft. Später erneut versuchen; das Video wird nicht doppelt hochgeladen."
            }
            if reason == "insufficientPermissions" {
                return "Google hat die nötige Berechtigung nicht erteilt. Die Upload-Verbindung erneut freigeben."
            }
            return "YouTube verweigert diese Zusatzaktion (403, \(reason)). Prüfe in YouTube Studio die Kanal-Freischaltung für eigene Vorschaubilder und die Google-Berechtigungen."
        case .rejected(let code, let reason): return "YouTube hat die Aktion abgelehnt (\(code), \(reason))."
        case .api(let code): return "YouTube hat die Aktion abgelehnt (\(code))."
        case .invalidResponse: return "YouTube hat keine gültige Antwort geliefert."
        case .invalidFile: return "Die Datei ist leer oder nicht lesbar."
        case .missingVideoID: return "Die YouTube-Video-ID fehlt."
        }
    }
}

public struct YouTubePackagingClient: Sendable {
    public let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    public func updateMetadata(
        videoID: String,
        title: String,
        description: String,
        tags: [String],
        categoryID: String?,
        session: URLSession = .shared
    ) async throws {
        guard !videoID.isEmpty else { throw YouTubePackagingError.missingVideoID }

        var snippet: [String: Any] = [
            "title": title,
            "description": description,
            "tags": tags
        ]
        if let categoryID, !categoryID.isEmpty {
            snippet["categoryId"] = categoryID
        }

        let body: [String: Any] = [
            "id": videoID,
            "snippet": snippet
        ]

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/youtube/v3/videos?part=snippet")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await session.data(for: request)
        try Self.validate(response, data: responseData)
    }

    public func setThumbnail(
        videoID: String,
        imageURL: URL,
        mimeType: String,
        session: URLSession = .shared
    ) async throws {
        guard !videoID.isEmpty else { throw YouTubePackagingError.missingVideoID }
        let data = try Data(contentsOf: imageURL)
        guard !data.isEmpty else { throw YouTubePackagingError.invalidFile }

        var components = URLComponents(
            string: "https://www.googleapis.com/upload/youtube/v3/thumbnails/set"
        )!
        components.queryItems = [
            .init(name: "videoId", value: videoID),
            .init(name: "uploadType", value: "media")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        try Self.validate(response, data: responseData)
    }

    public func uploadCaption(
        videoID: String,
        language: String,
        name: String,
        captionURL: URL,
        mimeType: String = "application/octet-stream",
        isDraft: Bool = false,
        session: URLSession = .shared
    ) async throws {
        guard !videoID.isEmpty else { throw YouTubePackagingError.missingVideoID }

        let mediaData = try Data(contentsOf: captionURL)
        guard !mediaData.isEmpty else { throw YouTubePackagingError.invalidFile }

        var components = URLComponents(
            string: "https://www.googleapis.com/upload/youtube/v3/captions"
        )!
        components.queryItems = [
            .init(name: "part", value: "snippet"),
            .init(name: "uploadType", value: "multipart")
        ]

        let boundary = "blackstock-\(UUID().uuidString)"
        let metadata: [String: Any] = [
            "snippet": [
                "videoId": videoID,
                "language": language,
                "name": name,
                "isDraft": isDraft
            ]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(mediaData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/related; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        try Self.validate(response, data: responseData)
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw YouTubePackagingError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = body["error"] as? [String: Any],
               let errors = error["errors"] as? [[String: Any]],
               let reason = errors.first?["reason"] as? String {
                // Only the provider's short reason code is persisted; never
                // include response bodies or authorization headers in errors.
                let safeReason = String(reason.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(80))
                throw YouTubePackagingError.rejected(http.statusCode, safeReason)
            }
            throw YouTubePackagingError.api(http.statusCode)
        }
    }
}
