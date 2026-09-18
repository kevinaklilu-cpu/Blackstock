import Foundation

public enum ExternalActionType: String, Codable, Sendable {
    case youtubeUpload = "YOUTUBE_UPLOAD"
    case youtubeThumbnailSet = "YOUTUBE_THUMBNAIL_SET"
    case youtubeMetadataUpdate = "YOUTUBE_METADATA_UPDATE"
}

public enum ExternalActionState: String, Codable, Sendable {
    case prepared = "PREPARED"
    case remoteSessionCreated = "REMOTE_SESSION_CREATED"
    case remoteCommitted = "REMOTE_COMMITTED"
    case reconciled = "RECONCILED"
    case failed = "FAILED"
}

public struct ExternalActionJournalEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let idempotencyKey: String
    public let actionType: ExternalActionType
    public let targetChannelID: String
    public var state: ExternalActionState
    public var remoteSessionURL: URL?
    public var remoteResourceID: String?
    public var nextByteOffset: Int64?
    public var lastError: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        idempotencyKey: String,
        actionType: ExternalActionType,
        targetChannelID: String,
        state: ExternalActionState = .prepared,
        remoteSessionURL: URL? = nil,
        remoteResourceID: String? = nil,
        nextByteOffset: Int64? = nil,
        lastError: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.actionType = actionType
        self.targetChannelID = targetChannelID
        self.state = state
        self.remoteSessionURL = remoteSessionURL
        self.remoteResourceID = remoteResourceID
        self.nextByteOffset = nextByteOffset
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public actor ExternalActionJournal {
    private var entries: [String: ExternalActionJournalEntry]

    public init(entries: [ExternalActionJournalEntry] = []) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.idempotencyKey, $0) })
    }

    public func entry(for idempotencyKey: String) -> ExternalActionJournalEntry? {
        entries[idempotencyKey]
    }

    public func upsert(_ entry: ExternalActionJournalEntry) {
        entries[entry.idempotencyKey] = entry
    }

    public func snapshot() -> [ExternalActionJournalEntry] {
        entries.values.sorted { $0.createdAt < $1.createdAt }
    }
}
