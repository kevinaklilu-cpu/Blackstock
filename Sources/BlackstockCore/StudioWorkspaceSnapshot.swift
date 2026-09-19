import Foundation

public struct StudioWorkspaceSnapshot: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let mediaAsset: ProductionMediaAsset?
    public let editGraph: EditGraph
    public let activityLedger: ActivityLedger
    public let storyboard: StoryboardPlan
    public let trimStart: Double
    public let trimEnd: Double
    public let transcript: LocalTranscript?
    public let captionURL: URL?
    public let renderArtifact: RenderArtifact?
    public let updatedAt: Date

    public init(
        projectID: UUID,
        mediaAsset: ProductionMediaAsset?,
        editGraph: EditGraph,
        activityLedger: ActivityLedger,
        storyboard: StoryboardPlan,
        trimStart: Double,
        trimEnd: Double,
        transcript: LocalTranscript?,
        captionURL: URL?,
        renderArtifact: RenderArtifact?,
        updatedAt: Date
    ) {
        self.projectID = projectID
        self.mediaAsset = mediaAsset
        self.editGraph = editGraph
        self.activityLedger = activityLedger
        self.storyboard = storyboard
        self.trimStart = max(trimStart, 0)
        self.trimEnd = max(trimEnd, self.trimStart)
        self.transcript = transcript
        self.captionURL = captionURL
        self.renderArtifact = renderArtifact
        self.updatedAt = updatedAt
    }
}

public enum WorkspaceSnapshotSource: String, Codable, Sendable {
    case primary = "PRIMARY"
    case backup = "BACKUP"
    case legacy = "LEGACY"
}

public struct WorkspaceSnapshotLoadResult: Sendable, Equatable {
    public let snapshot: StudioWorkspaceSnapshot
    public let source: WorkspaceSnapshotSource

    public init(
        snapshot: StudioWorkspaceSnapshot,
        source: WorkspaceSnapshotSource
    ) {
        self.snapshot = snapshot
        self.source = source
    }

    public var recoveredFromBackup: Bool {
        source == .backup
    }
}

private struct WorkspacePersistenceEnvelope: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let snapshot: StudioWorkspaceSnapshot
    let writtenAt: Date

    init(
        snapshot: StudioWorkspaceSnapshot,
        writtenAt: Date
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.snapshot = snapshot
        self.writtenAt = writtenAt
    }
}

public struct ProjectWorkspaceStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func projectDirectory(
        projectID: UUID
    ) throws -> URL {
        let directory = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func mediaDirectory(
        projectID: UUID
    ) throws -> URL {
        let directory = try projectDirectory(
            projectID: projectID
        )
        .appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func renderDirectory(
        projectID: UUID
    ) throws -> URL {
        let directory = try projectDirectory(
            projectID: projectID
        )
        .appendingPathComponent("Renders", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func captionDirectory(
        projectID: UUID
    ) throws -> URL {
        let directory = try projectDirectory(
            projectID: projectID
        )
        .appendingPathComponent("Captions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func importMedia(
        sourceURL: URL,
        projectID: UUID,
        assetID: UUID
    ) throws -> URL {
        let directory = try mediaDirectory(
            projectID: projectID
        )
        let ext = sourceURL.pathExtension
        let filename = ext.isEmpty
            ? assetID.uuidString
            : "\(assetID.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(
            filename
        )

        if FileManager.default.fileExists(
            atPath: destination.path
        ) {
            try FileManager.default.removeItem(
                at: destination
            )
        }
        try FileManager.default.copyItem(
            at: sourceURL,
            to: destination
        )
        return destination
    }

    public func save(
        _ snapshot: StudioWorkspaceSnapshot
    ) throws {
        let directory = try projectDirectory(
            projectID: snapshot.projectID
        )
        let primaryURL = directory.appendingPathComponent(
            "studio-workspace.json"
        )
        let backupURL = directory.appendingPathComponent(
            "studio-workspace.backup.json"
        )

        if FileManager.default.fileExists(
            atPath: primaryURL.path
        ) {
            if FileManager.default.fileExists(
                atPath: backupURL.path
            ) {
                try FileManager.default.removeItem(
                    at: backupURL
                )
            }
            try FileManager.default.copyItem(
                at: primaryURL,
                to: backupURL
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let envelope = WorkspacePersistenceEnvelope(
            snapshot: snapshot,
            writtenAt: Date()
        )
        let data = try encoder.encode(envelope)
        try data.write(
            to: primaryURL,
            options: [.atomic]
        )
    }

    public func restorePrimary(
        _ snapshot: StudioWorkspaceSnapshot
    ) throws {
        let directory = try projectDirectory(
            projectID: snapshot.projectID
        )
        let primaryURL = directory.appendingPathComponent(
            "studio-workspace.json"
        )
        if FileManager.default.fileExists(
            atPath: primaryURL.path
        ) {
            try FileManager.default.removeItem(
                at: primaryURL
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let envelope = WorkspacePersistenceEnvelope(
            snapshot: snapshot,
            writtenAt: Date()
        )
        try encoder.encode(envelope).write(
            to: primaryURL,
            options: [.atomic]
        )
    }

    public func load(
        projectID: UUID
    ) throws -> StudioWorkspaceSnapshot? {
        try loadResult(
            projectID: projectID
        )?.snapshot
    }

    public func loadResult(
        projectID: UUID
    ) throws -> WorkspaceSnapshotLoadResult? {
        let directory = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
        let primaryURL = directory.appendingPathComponent(
            "studio-workspace.json"
        )
        let backupURL = directory.appendingPathComponent(
            "studio-workspace.backup.json"
        )

        if let primary = try decodeSnapshot(
            from: primaryURL
        ) {
            return primary
        }

        if let backup = try decodeSnapshot(
            from: backupURL
        ) {
            return .init(
                snapshot: backup.snapshot,
                source: .backup
            )
        }

        return nil
    }

    private func decodeSnapshot(
        from url: URL
    ) throws -> WorkspaceSnapshotLoadResult? {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let envelope = try? decoder.decode(
            WorkspacePersistenceEnvelope.self,
            from: data
        ) {
            guard envelope.schemaVersion <= WorkspacePersistenceEnvelope.currentSchemaVersion else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return .init(
                snapshot: envelope.snapshot,
                source: .primary
            )
        }

        if let legacy = try? decoder.decode(
            StudioWorkspaceSnapshot.self,
            from: data
        ) {
            return .init(
                snapshot: legacy,
                source: .legacy
            )
        }

        return nil
    }
}
