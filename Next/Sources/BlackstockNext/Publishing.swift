import Foundation
import AppKit

struct PublishingProgress: Hashable {
    enum Phase: String, Hashable {
        case preparing = "Vorbereiten"
        case uploading = "Video"
        case thumbnail = "Thumbnail"
        case captions = "Untertitel"
        case playlist = "Playlist"
        case completed = "Fertig"
    }
    let phase: Phase
    let fraction: Double
    let detail: String
}

struct YouTubePublishingReceipt: Hashable {
    let videoID: String
    let watchURL: URL
    let completedAt: Date
}

final class ResumableYouTubePublisher {
    private let session: URLSession
    private let chunkSize = 8 * 1024 * 1024

    init(session: URLSession = .shared) { self.session = session }

    func createSession(fileURL: URL, publication: PublicationSettings, accessToken: String) async throws -> UploadRecoveryState {
        let size = try fileSize(fileURL)
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/videos")!
        components.queryItems = [
            .init(name: "uploadType", value: "resumable"),
            .init(name: "part", value: "snippet,status")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")

        var status: [String: Any] = [
            "privacyStatus": publication.scheduledAt == nil ? publication.privacy.rawValue : "private",
            "selfDeclaredMadeForKids": publication.madeForKids
        ]
        if let scheduled = publication.scheduledAt, scheduled > Date() {
            status["publishAt"] = ISO8601DateFormatter().string(from: scheduled)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "snippet": [
                "title": publication.title,
                "description": publication.description,
                "tags": publication.tags,
                "categoryId": publication.categoryID,
                "defaultLanguage": publication.defaultLanguage
            ],
            "status": status
        ])

        let (data, response) = try await session.data(for: request)
        try GoogleOAuthService.requireSuccess(response, data: data)
        guard let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location) else {
            throw YouTubeUploadError(message: "YouTube hat keine fortsetzbare Upload-Session geliefert.")
        }
        return .init(sessionURL: sessionURL, nextByte: 0, fileSize: size, updatedAt: Date())
    }

    func upload(
        fileURL: URL,
        recovery: UploadRecoveryState,
        accessToken: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (UploadRecoveryState, UploadReceipt?) {
        var state = recovery
        let current = try await remoteOffset(sessionURL: state.sessionURL, total: state.fileSize, accessToken: accessToken)
        state.nextByte = max(state.nextByte, current)
        if state.nextByte >= state.fileSize {
            return (state, nil)
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        while state.nextByte < state.fileSize {
            try handle.seek(toOffset: UInt64(state.nextByte))
            let remaining = state.fileSize - state.nextByte
            let count = Int(min(Int64(chunkSize), remaining))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else {
                throw YouTubeUploadError(message: "Videodatei konnte beim Upload nicht weiter gelesen werden.")
            }
            let start = state.nextByte
            let end = start + Int64(data.count) - 1
            var request = URLRequest(url: state.sessionURL)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
            request.setValue("bytes \(start)-\(end)/\(state.fileSize)", forHTTPHeaderField: "Content-Range")

            let (responseData, response) = try await session.upload(for: request, from: data)
            guard let http = response as? HTTPURLResponse else {
                throw YouTubeUploadError(message: "YouTube-Upload lieferte keine gültige Antwort.")
            }
            if http.statusCode == 308 {
                state.nextByte = nextOffset(from: http) ?? (end + 1)
                state.updatedAt = Date()
                onProgress(Double(state.nextByte) / Double(max(1, state.fileSize)))
                continue
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = errorMessage(responseData) ?? "YouTube-Upload wurde unterbrochen. Er kann fortgesetzt werden."
                throw YouTubeUploadError(message: message)
            }
            let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            guard let videoID = object?["id"] as? String, !videoID.isEmpty else {
                throw YouTubeUploadError(message: "YouTube hat nach dem Upload keine Video-ID geliefert.")
            }
            state.nextByte = state.fileSize
            state.updatedAt = Date()
            onProgress(1)
            return (state, .init(videoID: videoID, uploadedAt: Date()))
        }
        return (state, nil)
    }

    func uploadThumbnail(imageURL: URL, videoID: String, accessToken: String) async throws {
        let data = try Data(contentsOf: imageURL)
        guard data.count <= 2 * 1024 * 1024 else {
            throw YouTubeUploadError(message: "Das Thumbnail ist größer als 2 MB.")
        }
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/thumbnails/set")!
        components.queryItems = [.init(name: "videoId", value: videoID), .init(name: "uploadType", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType(for: imageURL), forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.upload(for: request, from: data)
        try GoogleOAuthService.requireSuccess(response, data: responseData)
    }

    func uploadCaptions(vtt: String, language: String, name: String, videoID: String, accessToken: String) async throws {
        let boundary = "blackstock-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: [
            "snippet": ["videoId": videoID, "language": language, "name": name, "isDraft": false]
        ])
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: text/vtt; charset=UTF-8\r\n\r\n".utf8))
        body.append(Data(vtt.utf8))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/captions")!
        components.queryItems = [.init(name: "part", value: "snippet"), .init(name: "uploadType", value: "multipart")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await session.upload(for: request, from: body)
        try GoogleOAuthService.requireSuccess(response, data: responseData)
    }

    private func remoteOffset(sessionURL: URL, total: Int64, accessToken: String) async throws -> Int64 {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes */\(total)", forHTTPHeaderField: "Content-Range")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return 0 }
        if http.statusCode == 308 { return nextOffset(from: http) ?? 0 }
        if (200..<300).contains(http.statusCode) { return total }
        if http.statusCode == 404 || http.statusCode == 410 {
            throw YouTubeUploadError(message: "Die gespeicherte Upload-Session ist abgelaufen. Blackstock startet beim nächsten Versuch eine neue Session.")
        }
        throw YouTubeUploadError(message: errorMessage(data) ?? "Upload-Status konnte nicht geprüft werden.")
    }

    private func nextOffset(from response: HTTPURLResponse) -> Int64? {
        guard let range = response.value(forHTTPHeaderField: "Range"), let dash = range.lastIndex(of: "-") else { return nil }
        return Int64(range[range.index(after: dash)...]).map { $0 + 1 }
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    private func errorMessage(_ data: Data) -> String? {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (root?["error"] as? [String: Any])?["message"] as? String
    }
}

struct CaptionFileBuilder {
    func webVTT(cues: [CaptionCue]) -> String {
        var lines = ["WEBVTT", ""]
        for cue in cues {
            lines.append("\(time(cue.start)) --> \(time(cue.end))")
            lines.append(cue.text.replacingOccurrences(of: "\n", with: " "))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func time(_ seconds: Double) -> String {
        let millis = Int(max(0, seconds) * 1000)
        let h = millis / 3_600_000
        let m = (millis / 60_000) % 60
        let s = (millis / 1000) % 60
        let ms = millis % 1000
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}

final class PublishingCoordinator {
    private let publisher: ResumableYouTubePublisher
    private let dataService: YouTubeDataService

    init(publisher: ResumableYouTubePublisher = .init(), dataService: YouTubeDataService = .init()) {
        self.publisher = publisher
        self.dataService = dataService
    }

    func publish(
        project: BlackstockProject,
        accessToken: String,
        onRecovery: @escaping @Sendable (UploadRecoveryState) -> Void,
        onProgress: @escaping @Sendable (PublishingProgress) -> Void
    ) async throws -> (YouTubePublishingReceipt, UploadRecoveryState) {
        guard let renderedPath = project.renderedPath else { throw YouTubeUploadError(message: "Es gibt noch keinen fertigen Export.") }
        let fileURL = URL(fileURLWithPath: renderedPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw YouTubeUploadError(message: "Die fertige Videodatei wurde nicht gefunden.") }

        onProgress(.init(phase: .preparing, fraction: 0.02, detail: "Veröffentlichung wird vorbereitet"))
        var recovery: UploadRecoveryState
        if let existing = project.uploadRecovery {
            recovery = existing
        } else {
            recovery = try await publisher.createSession(fileURL: fileURL, publication: project.publication, accessToken: accessToken)
            onRecovery(recovery)
        }

        onProgress(.init(phase: .uploading, fraction: 0.05, detail: "Video wird fortsetzbar hochgeladen"))
        let result = try await publisher.upload(fileURL: fileURL, recovery: recovery, accessToken: accessToken) { fraction in
            onProgress(.init(phase: .uploading, fraction: 0.05 + fraction * 0.78, detail: "Video \(Int(fraction * 100)) %"))
        }
        recovery = result.0
        onRecovery(recovery)
        guard let receipt = result.1 else {
            throw YouTubeUploadError(message: "Upload ist vollständig, aber die Video-ID muss von YouTube erneut geladen werden.")
        }

        if let thumbnailPath = project.publication.thumbnailPath, FileManager.default.fileExists(atPath: thumbnailPath) {
            onProgress(.init(phase: .thumbnail, fraction: 0.86, detail: "Thumbnail wird gesetzt"))
            try await publisher.uploadThumbnail(imageURL: URL(fileURLWithPath: thumbnailPath), videoID: receipt.videoID, accessToken: accessToken)
        }
        if !project.captions.isEmpty {
            onProgress(.init(phase: .captions, fraction: 0.91, detail: "Untertitel werden übertragen"))
            let vtt = CaptionFileBuilder().webVTT(cues: project.captions)
            try await publisher.uploadCaptions(vtt: vtt, language: project.publication.defaultLanguage, name: "Blackstock", videoID: receipt.videoID, accessToken: accessToken)
        }
        if let playlistID = project.publication.playlistID, !playlistID.isEmpty {
            onProgress(.init(phase: .playlist, fraction: 0.96, detail: "Playlist wird zugeordnet"))
            try await dataService.add(videoID: receipt.videoID, toPlaylist: playlistID, accessToken: accessToken)
        }
        onProgress(.init(phase: .completed, fraction: 1, detail: "Auf YouTube veröffentlicht"))
        let watchURL = URL(string: "https://www.youtube.com/watch?v=\(receipt.videoID)")!
        return (.init(videoID: receipt.videoID, watchURL: watchURL, completedAt: Date()), recovery)
    }
}
