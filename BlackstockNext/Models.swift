import Foundation

public enum BlackstockRoute: String, CaseIterable, Identifiable, Codable {
    case channel = "Kanal"
    case opportunities = "Chancen"
    case cut = "Schnitt"
    case quality = "Prüfungen"
    case settings = "Einstellungen"
    public var id: String { rawValue }
}

public enum SourceAccess: String, Codable, CaseIterable, Identifiable {
    case youtubeNative = "YouTube nativ"
    case localLicensed = "Lokale erlaubte Quelle"
    case analysisOnly = "Nur Analyse"
    public var id: String { rawValue }
}

public enum AspectMode: String, Codable, CaseIterable, Identifiable {
    case original = "Original"
    case vertical = "9:16"
    case square = "1:1"
    public var id: String { rawValue }
}

public struct ChannelDNA: Codable, Equatable {
    public var primaryTopic: String
    public var contentPillars: [String]
    public var keywords: [String]
    public var languageHint: String
    public var sampleSize: Int
    public var updatedAt: Date

    public init(primaryTopic: String = "Noch nicht erkannt", contentPillars: [String] = [], keywords: [String] = [], languageHint: String = "Unbekannt", sampleSize: Int = 0, updatedAt: Date = .now) {
        self.primaryTopic = primaryTopic
        self.contentPillars = contentPillars
        self.keywords = keywords
        self.languageHint = languageHint
        self.sampleSize = sampleSize
        self.updatedAt = updatedAt
    }
}

public struct ConnectedChannel: Codable, Identifiable, Equatable {
    public var id: UUID
    public var youtubeChannelID: String
    public var handle: String?
    public var name: String
    public var thumbnailURL: URL?
    public var subscriberCount: Int
    public var videoCount: Int
    public var dna: ChannelDNA

    public init(id: UUID = UUID(), youtubeChannelID: String, handle: String? = nil, name: String, thumbnailURL: URL? = nil, subscriberCount: Int = 0, videoCount: Int = 0, dna: ChannelDNA = ChannelDNA()) {
        self.id = id
        self.youtubeChannelID = youtubeChannelID
        self.handle = handle
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.subscriberCount = subscriberCount
        self.videoCount = videoCount
        self.dna = dna
    }
}

public struct PublicVideo: Codable, Identifiable, Hashable {
    public var id: String { videoID }
    public var videoID: String
    public var title: String
    public var description: String
    public var channelTitle: String
    public var channelID: String
    public var publishedAt: Date
    public var thumbnailURL: URL?
    public var viewCount: Int
    public var likeCount: Int
    public var commentCount: Int
    public var durationSeconds: Double
    public var categoryID: String

    public init(videoID: String, title: String, description: String, channelTitle: String, channelID: String, publishedAt: Date, thumbnailURL: URL?, viewCount: Int, likeCount: Int, commentCount: Int, durationSeconds: Double, categoryID: String) {
        self.videoID = videoID
        self.title = title
        self.description = description
        self.channelTitle = channelTitle
        self.channelID = channelID
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.durationSeconds = durationSeconds
        self.categoryID = categoryID
    }
}

public struct Opportunity: Codable, Identifiable, Equatable {
    public var id: String { video.videoID }
    public var video: PublicVideo
    public var channelFit: Double
    public var momentum: Double
    public var freshness: Double
    public var score: Double
    public var reasons: [String]
    public var access: SourceAccess

    public init(video: PublicVideo, channelFit: Double, momentum: Double, freshness: Double, score: Double, reasons: [String], access: SourceAccess = .youtubeNative) {
        self.video = video
        self.channelFit = channelFit
        self.momentum = momentum
        self.freshness = freshness
        self.score = score
        self.reasons = reasons
        self.access = access
    }
}

public struct TranscriptSegment: Codable, Identifiable, Equatable {
    public var id: UUID
    public var start: Double
    public var duration: Double
    public var text: String
    public var confidence: Double

    public init(id: UUID = UUID(), start: Double, duration: Double, text: String, confidence: Double) {
        self.id = id
        self.start = start
        self.duration = duration
        self.text = text
        self.confidence = confidence
    }
}

public struct ClipMoment: Codable, Identifiable, Equatable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var score: Double
    public var title: String
    public var rationale: [String]
    public var previewText: String
    public var source: String

    public init(id: UUID = UUID(), start: Double, end: Double, score: Double, title: String, rationale: [String], previewText: String, source: String) {
        self.id = id
        self.start = start
        self.end = end
        self.score = score
        self.title = title
        self.rationale = rationale
        self.previewText = previewText
        self.source = source
    }

    public var duration: Double { max(0, end - start) }
}

public struct MediaInfo: Codable, Equatable {
    public var url: URL
    public var duration: Double
    public var width: Int
    public var height: Int
    public var fps: Double
    public var hasAudio: Bool
    public var fileSizeBytes: Int64

    public init(url: URL, duration: Double, width: Int, height: Int, fps: Double, hasAudio: Bool, fileSizeBytes: Int64) {
        self.url = url
        self.duration = duration
        self.width = width
        self.height = height
        self.fps = fps
        self.hasAudio = hasAudio
        self.fileSizeBytes = fileSizeBytes
    }
}

public struct QualityReport: Codable, Equatable {
    public var passed: Bool
    public var checks: [String]
    public var warnings: [String]
    public var output: MediaInfo?

    public init(passed: Bool, checks: [String], warnings: [String], output: MediaInfo? = nil) {
        self.passed = passed
        self.checks = checks
        self.warnings = warnings
        self.output = output
    }
}

public struct CutProject: Codable, Identifiable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var channelID: UUID?
    public var youtubeVideoID: String?
    public var sourceURL: URL?
    public var sourceAccess: SourceAccess
    public var sourceRightsConfirmed: Bool
    public var mediaInfo: MediaInfo?
    public var transcript: [TranscriptSegment]
    public var moments: [ClipMoment]
    public var selectedMomentID: UUID?
    public var aspect: AspectMode
    public var exportedURL: URL?
    public var qualityReport: QualityReport?

    public init(id: UUID = UUID(), createdAt: Date = .now, channelID: UUID? = nil, youtubeVideoID: String? = nil, sourceURL: URL? = nil, sourceAccess: SourceAccess = .analysisOnly, sourceRightsConfirmed: Bool = false, mediaInfo: MediaInfo? = nil, transcript: [TranscriptSegment] = [], moments: [ClipMoment] = [], selectedMomentID: UUID? = nil, aspect: AspectMode = .original, exportedURL: URL? = nil, qualityReport: QualityReport? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.channelID = channelID
        self.youtubeVideoID = youtubeVideoID
        self.sourceURL = sourceURL
        self.sourceAccess = sourceAccess
        self.sourceRightsConfirmed = sourceRightsConfirmed
        self.mediaInfo = mediaInfo
        self.transcript = transcript
        self.moments = moments
        self.selectedMomentID = selectedMomentID
        self.aspect = aspect
        self.exportedURL = exportedURL
        self.qualityReport = qualityReport
    }

    public var selectedMoment: ClipMoment? {
        guard let selectedMomentID else { return nil }
        return moments.first(where: { $0.id == selectedMomentID })
    }
}

public enum BlackstockError: LocalizedError {
    case missingAPIKey
    case invalidChannel
    case invalidResponse
    case noVideoTrack
    case noMoments
    case rightsNotConfirmed
    case exportFailed(String)
    case speechUnavailable
    case speechPermissionDenied

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Für öffentliche YouTube-Daten fehlt der API-Schlüssel."
        case .invalidChannel: return "Der YouTube-Kanal konnte nicht aufgelöst werden."
        case .invalidResponse: return "YouTube hat eine unerwartete Antwort geliefert."
        case .noVideoTrack: return "Die ausgewählte Datei enthält keine nutzbare Videospur."
        case .noMoments: return "Es wurden noch keine belastbaren Schnittmomente gefunden."
        case .rightsNotConfirmed: return "Lokaler Export ist erst nach Bestätigung der Nutzungsrechte möglich."
        case .exportFailed(let message): return "Export fehlgeschlagen: \(message)"
        case .speechUnavailable: return "Spracherkennung ist für diese Quelle derzeit nicht verfügbar."
        case .speechPermissionDenied: return "Spracherkennung wurde nicht erlaubt."
        }
    }
}
