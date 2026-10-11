import Foundation

public enum MediaSourceProvider: String, Codable, Sendable {
    case youtube
    case localFile
    case directRemote
    case cloudStorage
    case approvedPartner
}

public enum MediaResolutionStatus: String, Codable, Sendable {
    case playbackOnly = "PLAYBACK_ONLY"
    case ingestReady = "INGEST_READY"
    case sourceConnectionRequired = "SOURCE_CONNECTION_REQUIRED"
    case providerApprovalRequired = "PROVIDER_APPROVAL_REQUIRED"
}

public struct MediaSourceReference: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let provider: MediaSourceProvider
    public let pageURL: URL
    public let externalID: String?
    public let discoveredAt: Date

    public init(
        id: UUID = UUID(),
        provider: MediaSourceProvider,
        pageURL: URL,
        externalID: String?,
        discoveredAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.pageURL = pageURL
        self.externalID = externalID
        self.discoveredAt = discoveredAt
    }
}

public struct RemoteIngestProviderAuthorization: Codable, Sendable, Equatable {
    public let providerID: String
    public let supportsYouTubeLinks: Bool
    public let youtubeWrittenApprovalReference: String?
    public let verifiedAt: Date?

    public init(
        providerID: String,
        supportsYouTubeLinks: Bool,
        youtubeWrittenApprovalReference: String?,
        verifiedAt: Date?
    ) {
        self.providerID = providerID
        self.supportsYouTubeLinks = supportsYouTubeLinks
        self.youtubeWrittenApprovalReference = youtubeWrittenApprovalReference
        self.verifiedAt = verifiedAt
    }

    public var mayIngestYouTubeLinks: Bool {
        guard supportsYouTubeLinks,
              let reference = youtubeWrittenApprovalReference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty,
              verifiedAt != nil else { return false }
        return true
    }
}

public struct ResolvedMediaSource: Codable, Sendable, Equatable {
    public let source: MediaSourceReference
    public let status: MediaResolutionStatus
    public let ingestProviderID: String?
    public let explanation: String

    public init(
        source: MediaSourceReference,
        status: MediaResolutionStatus,
        ingestProviderID: String?,
        explanation: String
    ) {
        self.source = source
        self.status = status
        self.ingestProviderID = ingestProviderID
        self.explanation = explanation
    }
}

public struct MediaSourceResolver: Sendable {
    public init() {}

    public func resolve(
        _ source: MediaSourceReference,
        approvedProvider: RemoteIngestProviderAuthorization?,
        localYouTubeDownloaderAvailable: Bool = false
    ) -> ResolvedMediaSource {
        switch source.provider {
        case .youtube:
            if localYouTubeDownloaderAvailable {
                return .init(source: source, status: .ingestReady,
                    ingestProviderID: "local-youtube-download",
                    explanation: "Das Video kann auf diesen Mac geladen und danach geschnitten werden.")
            }
            if let approvedProvider, approvedProvider.mayIngestYouTubeLinks {
                return .init(
                    source: source,
                    status: .ingestReady,
                    ingestProviderID: approvedProvider.providerID,
                    explanation: "YouTube-Link kann über einen verifizierten, freigegebenen Ingest-Provider verarbeitet werden."
                )
            }
            return .init(
                source: source,
                status: .providerApprovalRequired,
                ingestProviderID: nil,
                explanation: "Der Link bleibt abspielbar und recherchierbar. Verarbeitung wird erst freigeschaltet, wenn ein verifizierter YouTube-Ingest-Provider verfügbar ist."
            )

        case .localFile, .directRemote, .cloudStorage, .approvedPartner:
            return .init(
                source: source,
                status: .ingestReady,
                ingestProviderID: approvedProvider?.providerID,
                explanation: "Quelle kann nach Rechteprüfung in die Produktion übernommen werden."
            )
        }
    }
}
