import Foundation

public enum ExternalActionType: String, Codable, Sendable {
    case youtubeUpload = "YOUTUBE_UPLOAD"
    case youtubeThumbnailSet = "YOUTUBE_THUMBNAIL_SET"
    case youtubeMetadataUpdate = "YOUTUBE_METADATA_UPDATE"
    case youtubeCaptionUpload = "YOUTUBE_CAPTION_UPLOAD"
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

public enum ExternalActionJournalError: Error, Sendable, Equatable {
    case loadFailed(String)
    case persistenceFailed(String)
}

public actor ExternalActionJournal {
    private var entries: [String: ExternalActionJournalEntry]
    private let persistenceURL: URL?

    public init(
        entries: [ExternalActionJournalEntry] = [],
        persistenceURL: URL? = nil
    ) {
        self.entries = Dictionary(
            uniqueKeysWithValues: entries.map {
                ($0.idempotencyKey, $0)
            }
        )
        self.persistenceURL = persistenceURL
    }

    public static func persistent(
        at url: URL
    ) throws -> ExternalActionJournal {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ExternalActionJournal(
                entries: [],
                persistenceURL: url
            )
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode(
                [ExternalActionJournalEntry].self,
                from: data
            )
            return ExternalActionJournal(
                entries: entries,
                persistenceURL: url
            )
        } catch {
            throw ExternalActionJournalError.loadFailed(
                error.localizedDescription
            )
        }
    }

    public func entry(
        for idempotencyKey: String
    ) -> ExternalActionJournalEntry? {
        entries[idempotencyKey]
    }

    public func upsert(
        _ entry: ExternalActionJournalEntry
    ) throws {
        let previous = entries[entry.idempotencyKey]
        entries[entry.idempotencyKey] = entry

        do {
            try persistIfNeeded()
        } catch {
            if let previous {
                entries[entry.idempotencyKey] = previous
            } else {
                entries.removeValue(
                    forKey: entry.idempotencyKey
                )
            }
            throw error
        }
    }

    public func snapshot() -> [ExternalActionJournalEntry] {
        entries.values.sorted {
            $0.createdAt < $1.createdAt
        }
    }

    public func persistenceLocation() -> URL? {
        persistenceURL
    }

    private func persistIfNeeded() throws {
        guard let persistenceURL else { return }

        do {
            let directory = persistenceURL
                .deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]

            let snapshot = entries.values.sorted {
                $0.createdAt < $1.createdAt
            }
            let data = try encoder.encode(snapshot)
            try data.write(
                to: persistenceURL,
                options: [.atomic]
            )
        } catch {
            throw ExternalActionJournalError.persistenceFailed(
                error.localizedDescription
            )
        }
    }
}
