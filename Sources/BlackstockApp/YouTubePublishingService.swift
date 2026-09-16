#if os(macOS)
import Foundation
import BlackstockCore

enum YouTubePublishingError: LocalizedError {
    case missingAuthentication
    case missingRenderedVideo
    case tokenRefreshFailed(String)
    case uploadInitializationFailed(String)
    case uploadFailed(String)
    case thumbnailFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthentication: return "Der Zielkanal ist nicht mehr mit YouTube verbunden."
        case .missingRenderedVideo: return "Vor dem Upload muss ein finales Video gerendert werden."
        case .tokenRefreshFailed(let message): return message
        case .uploadInitializationFailed(let message): return message
        case .uploadFailed(let message): return message
        case .thumbnailFailed(let message): return message
        }
    }
}

extension GoogleYouTubeAuth {
    static func freshAccessToken(channelID: String) async throws -> String {
        let refreshToken = Keychain.read("youtube-refresh-\(channelID)")
        let existingAccess = Keychain.read("youtube-access-\(channelID)")
        guard !refreshToken.isEmpty || !existingAccess.isEmpty else { throw YouTubePublishingError.missingAuthentication }
        guard !refreshToken.isEmpty else { return existingAccess }

        let clientID = configuredClientID
        guard !clientID.isEmpty else { return existingAccess }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if !existingAccess.isEmpty { return existingAccess }
            throw YouTubePublishingError.tokenRefreshFailed("YouTube konnte die Anmeldung nicht erneuern.")
        }
        let token = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)
        Keychain.write(token.accessToken, account: "youtube-access-\(channelID)")
        return token.accessToken
    }

    private static func formEncode(_ values: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return values.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

struct YouTubePublishingService: Sendable {
    func upload(project: Project, channelID: String, privacyStatus: String = "private", progress: @escaping @MainActor (Double, String) -> Void) async throws -> String {
        guard let fileURL = project.renderedOutputURL else { throw YouTubePublishingError.missingRenderedVideo }
        let accessToken = try await GoogleYouTubeAuth.freshAccessToken(channelID: channelID)
        await progress(0.03, "Upload wird vorbereitet …")

        let metadata: [String: Any] = [
            "snippet": [
                "title": (project.publishTitle ?? project.title).trimmingCharacters(in: .whitespacesAndNewlines),
                "description": (project.publishDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                "tags": project.publishTags ?? []
            ],
            "status": [
                "privacyStatus": privacyStatus,
                "selfDeclaredMadeForKids": false
            ]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        var initializer = URLRequest(url: URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status")!)
        initializer.httpMethod = "POST"
        initializer.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        initializer.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initializer.setValue(mimeType(for: fileURL), forHTTPHeaderField: "X-Upload-Content-Type")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path), let size = attributes[.size] as? NSNumber {
            initializer.setValue(size.stringValue, forHTTPHeaderField: "X-Upload-Content-Length")
        }
        initializer.httpBody = metadataData

        let (initData, initResponse) = try await URLSession.shared.data(for: initializer)
        guard let initHTTP = initResponse as? HTTPURLResponse, (200..<300).contains(initHTTP.statusCode), let location = initHTTP.value(forHTTPHeaderField: "Location"), let uploadURL = URL(string: location) else {
            let message = Self.apiMessage(from: initData) ?? "YouTube konnte keinen Upload starten."
            throw YouTubePublishingError.uploadInitializationFailed(message)
        }

        await progress(0.12, "Video wird zu YouTube hochgeladen …")
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue(mimeType(for: fileURL), forHTTPHeaderField: "Content-Type")
        let (uploadedData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: fileURL)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse, (200..<300).contains(uploadHTTP.statusCode) else {
            let message = Self.apiMessage(from: uploadedData) ?? "Der YouTube-Upload ist fehlgeschlagen."
            throw YouTubePublishingError.uploadFailed(message)
        }
        let uploaded = try JSONDecoder().decode(UploadedVideo.self, from: uploadedData)
        await progress(0.9, "Video hochgeladen. Thumbnail wird gesetzt …")

        if let thumbnailURL = project.thumbnailURL {
            try await setThumbnail(videoID: uploaded.id, fileURL: thumbnailURL, accessToken: accessToken)
        }
        await progress(1, "Upload abgeschlossen")
        return uploaded.id
    }

    private func setThumbnail(videoID: String, fileURL: URL, accessToken: String) async throws {
        let data = try Data(contentsOf: fileURL)
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/thumbnails/set")!
        components.queryItems = [URLQueryItem(name: "videoId", value: videoID), URLQueryItem(name: "uploadType", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType(for: fileURL), forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = Self.apiMessage(from: responseData) ?? "Das Video ist online, aber das Thumbnail konnte nicht gesetzt werden."
            throw YouTubePublishingError.thumbnailFailed(message)
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        default: return "video/mp4"
        }
    }

    private static func apiMessage(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(YouTubeAPIErrorEnvelope.self, from: data) else { return nil }
        return envelope.error.message
    }
}

private struct RefreshTokenResponse: Decodable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}
private struct UploadedVideo: Decodable { let id: String }
private struct YouTubeAPIErrorEnvelope: Decodable { let error: YouTubeAPIErrorBody }
private struct YouTubeAPIErrorBody: Decodable { let message: String }
#endif
