import Foundation
import AVFoundation

struct UploadMetadata: Hashable {
    var title: String
    var description: String
    var tags: [String]
    var categoryID: String
    var privacyStatus: String
    var madeForKids: Bool
}

struct UploadReceipt: Hashable {
    let videoID: String
    let uploadedAt: Date
}

struct YouTubeUploadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class YouTubeUploadService {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func startResumableUpload(fileURL: URL, metadata: UploadMetadata, accessToken: String) async throws -> URL {
        var components = URLComponents(string: "https://www.googleapis.com/upload/youtube/v3/videos")!
        components.queryItems = [
            .init(name: "uploadType", value: "resumable"),
            .init(name: "part", value: "snippet,status")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let length = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        request.setValue(String(length), forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("video/*", forHTTPHeaderField: "X-Upload-Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "snippet": [
                "title": metadata.title,
                "description": metadata.description,
                "tags": metadata.tags,
                "categoryId": metadata.categoryID
            ],
            "status": [
                "privacyStatus": metadata.privacyStatus,
                "selfDeclaredMadeForKids": metadata.madeForKids
            ]
        ])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location) else {
            throw YouTubeUploadError(message: "YouTube konnte keine fortsetzbare Upload-Session starten.")
        }
        return url
    }

    func upload(fileURL: URL, sessionURL: URL, accessToken: String) async throws -> UploadReceipt {
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("video/*", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YouTubeUploadError(message: "YouTube-Upload fehlgeschlagen. Die Upload-Session kann erneut verwendet werden.")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["id"] as? String, !id.isEmpty else {
            throw YouTubeUploadError(message: "YouTube hat keine Video-ID zurückgegeben.")
        }
        return .init(videoID: id, uploadedAt: Date())
    }
}

struct ExportSpec: Hashable {
    enum Orientation: Hashable { case landscape, portrait }
    var orientation: Orientation
    var targetFPS: Double
    var maxLongEdge: CGFloat
    var includeCaptions: Bool
}

struct SourceProbe: Hashable {
    let duration: Double
    let naturalSize: CGSize
    let frameRate: Double
    let hasAudio: Bool
}

final class LocalMediaInspector {
    func probe(url: URL) async throws -> SourceProbe {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw YouTubeUploadError(message: "Die Quelldatei hat keine gültige Dauer.") }
        let videos = try await asset.loadTracks(withMediaType: .video)
        guard let video = videos.first else { throw YouTubeUploadError(message: "Die Quelldatei enthält keine Videospur.") }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let transformed = size.applying(transform)
        let displaySize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        let fps = Double(try await video.load(.nominalFrameRate))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        return .init(duration: duration, naturalSize: displaySize, frameRate: fps > 0 ? fps : 30, hasAudio: !audio.isEmpty)
    }
}

struct QualityDecision: Hashable {
    enum Action: Hashable { case pass, autoFix, warn, block }
    let action: Action
    let messages: [String]
}

struct MassMarketQualityPolicy {
    func decide(captions: CaptionQualityReport?, source: SourceProbe?, rights: RightsDecision) -> QualityDecision {
        var messages: [String] = []
        switch rights {
        case .analysisOnly(let reason):
            return .init(action: .block, messages: [reason])
        case .youtubeNativeRemix:
            return .init(action: .pass, messages: ["YouTube-native Verarbeitung; kein lokaler Quell-Export nötig."])
        case .localExportAllowed:
            break
        }

        guard let source else {
            return .init(action: .block, messages: ["Die Quelldatei konnte technisch nicht gelesen werden."])
        }
        if source.naturalSize.width < 640 || source.naturalSize.height < 360 {
            messages.append("Niedrige Quellauflösung – Export wird nicht künstlich überschärft.")
        }
        if let captions {
            if !captions.blockingIssues.isEmpty || captions.score < 90 {
                messages.append("Captions werden automatisch neu segmentiert und auf Lesbarkeit optimiert.")
                return .init(action: .autoFix, messages: messages + captions.blockingIssues + captions.warnings)
            }
        }
        if !messages.isEmpty { return .init(action: .warn, messages: messages) }
        return .init(action: .pass, messages: ["Technische Qualitätsprüfung bestanden."])
    }
}

struct ProductionQualityDefaults {
    func exportSpec(for source: SourceProbe, portrait: Bool, captions: Bool) -> ExportSpec {
        let longEdge = max(source.naturalSize.width, source.naturalSize.height)
        let cap: CGFloat = longEdge >= 3840 ? 3840 : (longEdge >= 1920 ? 1920 : max(1280, longEdge))
        let fps: Double
        if source.frameRate >= 50 { fps = min(60, source.frameRate) }
        else if source.frameRate >= 29 { fps = min(30, source.frameRate) }
        else { fps = source.frameRate }
        return .init(orientation: portrait ? .portrait : .landscape, targetFPS: max(24, fps), maxLongEdge: cap, includeCaptions: captions)
    }
}

struct AutoFixCoordinator {
    let captionEngine = CaptionEngine()

    func repairCaptions(words: [TranscriptWord], videoDuration: Double) -> ([CaptionCue], CaptionQualityReport) {
        let cues = captionEngine.cues(from: words)
        let report = captionEngine.qualityReport(cues: cues, videoDuration: videoDuration)
        return (cues, report)
    }
}
