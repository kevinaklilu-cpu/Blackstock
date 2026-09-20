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
    public let burnInCaptionsEnabled: Bool?
    public let captionVisualStyle: CaptionVisualStyle?
    public let renderArtifact: RenderArtifact?
    public let supplementalCaptures: [SupplementalCaptureAsset]?
    public let savedClipSelections: [SavedClipSelection]?
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
        burnInCaptionsEnabled: Bool? = nil,
        captionVisualStyle: CaptionVisualStyle? = nil,
        renderArtifact: RenderArtifact?,
        supplementalCaptures: [SupplementalCaptureAsset] = [],
        savedClipSelections: [SavedClipSelection] = [],
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
        self.burnInCaptionsEnabled =
            burnInCaptionsEnabled
        self.captionVisualStyle =
            captionVisualStyle
        self.renderArtifact = renderArtifact
        self.supplementalCaptures = supplementalCaptures
        self.savedClipSelections = savedClipSelections
        self.updatedAt = updatedAt
    }
}

public enum ProjectPackagingAssetKind: String, Codable, Sendable {
    case thumbnail = "Thumbnails"
    case caption = "Captions"
}

public enum PublishPreparationSchema {
    public static let legacyUnversioned = 1
    public static let current = 2
}

public enum PublishPreparationMigrationError: Error, Sendable, Equatable {
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

private struct PublishPreparationEnvelope: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let snapshot: PublishPreparationSnapshot
}

public enum WorkspaceSchema {
    public static let legacyUnversioned = 1
    public static let current = 3
}

public enum WorkspaceMigrationError: Error, Sendable, Equatable {
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

private struct StudioWorkspaceEnvelope: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let snapshot: StudioWorkspaceSnapshot
}

public struct WorkspaceLoadResult: Sendable, Equatable {
    public let snapshot: StudioWorkspaceSnapshot?
    public let recoveredFromBackup: Bool
    public let migratedFromSchemaVersion: Int?

    public init(
        snapshot: StudioWorkspaceSnapshot?,
        recoveredFromBackup: Bool,
        migratedFromSchemaVersion: Int? = nil
    ) {
        self.snapshot = snapshot
        self.recoveredFromBackup = recoveredFromBackup
        self.migratedFromSchemaVersion = migratedFromSchemaVersion
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

    public func captureDirectory(
        projectID: UUID
    ) throws -> URL {
        let directory = try projectDirectory(
            projectID: projectID
        )
        .appendingPathComponent("Captures", isDirectory: true)
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

    public func packagingAssetDirectory(
        projectID: UUID,
        kind: ProjectPackagingAssetKind
    ) throws -> URL {
        let directory = try projectDirectory(
            projectID: projectID
        )
        .appendingPathComponent(kind.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    public func importPackagingAsset(
        sourceURL: URL,
        projectID: UUID,
        assetID: UUID,
        kind: ProjectPackagingAssetKind
    ) throws -> URL {
        let directory = try packagingAssetDirectory(
            projectID: projectID,
            kind: kind
        )
        return try copyProjectFile(
            sourceURL: sourceURL,
            destinationDirectory: directory,
            assetID: assetID
        )
    }

    public func importMedia(
        sourceURL: URL,
        projectID: UUID,
        assetID: UUID
    ) throws -> URL {
        let directory = try mediaDirectory(
            projectID: projectID
        )
        return try copyProjectFile(
            sourceURL: sourceURL,
            destinationDirectory: directory,
            assetID: assetID
        )
    }

    public func importSupplementalCapture(
        sourceURL: URL,
        projectID: UUID,
        assetID: UUID
    ) throws -> URL {
        let directory = try captureDirectory(
            projectID: projectID
        )
        return try copyProjectFile(
            sourceURL: sourceURL,
            destinationDirectory: directory,
            assetID: assetID
        )
    }

    private func copyProjectFile(
        sourceURL: URL,
        destinationDirectory: URL,
        assetID: UUID
    ) throws -> URL {
        let ext = sourceURL.pathExtension
        let filename = ext.isEmpty
            ? assetID.uuidString
            : "\(assetID.uuidString).\(ext)"
        let destination = destinationDirectory.appendingPathComponent(
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

    public func savePublishPreparation(
        _ snapshot: PublishPreparationSnapshot
    ) throws {
        let directory = try projectDirectory(
            projectID: snapshot.package.projectID
        )
        let url = directory.appendingPathComponent(
            "publish-preparation.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let envelope = PublishPreparationEnvelope(
            schemaVersion: PublishPreparationSchema.current,
            snapshot: snapshot
        )
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: [.atomic])
    }

    public func loadPublishPreparation(
        projectID: UUID
    ) throws -> PublishPreparationSnapshot? {
        let url = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "publish-preparation.json"
            )

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoded = try decodePublishPreparationData(
            data,
            expectedProjectID: projectID
        )
        if decoded.schemaVersion < PublishPreparationSchema.current {
            try savePublishPreparation(decoded.snapshot)
        }
        return decoded.snapshot
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

        if FileManager.default.fileExists(atPath: primaryURL.path),
           let primaryData = try? Data(contentsOf: primaryURL),
           (try? decodeWorkspaceData(
                primaryData,
                expectedProjectID: snapshot.projectID
           )) != nil {
            try primaryData.write(to: backupURL, options: [.atomic])
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let envelope = StudioWorkspaceEnvelope(
            schemaVersion: WorkspaceSchema.current,
            snapshot: snapshot
        )
        let data = try encoder.encode(envelope)
        try data.write(to: primaryURL, options: [.atomic])
    }

    public func load(
        projectID: UUID
    ) throws -> StudioWorkspaceSnapshot? {
        try loadWithRecovery(projectID: projectID).snapshot
    }

    public func loadWithRecovery(
        projectID: UUID
    ) throws -> WorkspaceLoadResult {
        let directory = rootURL.appendingPathComponent(
            projectID.uuidString,
            isDirectory: true
        )
        let primaryURL = directory.appendingPathComponent(
            "studio-workspace.json"
        )
        let backupURL = directory.appendingPathComponent(
            "studio-workspace.backup.json"
        )

        let primaryExists = FileManager.default.fileExists(
            atPath: primaryURL.path
        )
        let backupExists = FileManager.default.fileExists(
            atPath: backupURL.path
        )

        guard primaryExists || backupExists else {
            return WorkspaceLoadResult(
                snapshot: nil,
                recoveredFromBackup: false
            )
        }

        if primaryExists {
            do {
                let data = try Data(contentsOf: primaryURL)
                let decoded = try decodeWorkspaceData(
                    data,
                    expectedProjectID: projectID
                )
                return WorkspaceLoadResult(
                    snapshot: decoded.snapshot,
                    recoveredFromBackup: false,
                    migratedFromSchemaVersion: decoded.schemaVersion
                        < WorkspaceSchema.current
                        ? decoded.schemaVersion
                        : nil
                )
            } catch {
                guard backupExists else { throw error }
            }
        }

        let backupData = try Data(contentsOf: backupURL)
        let decoded = try decodeWorkspaceData(
            backupData,
            expectedProjectID: projectID
        )
        return WorkspaceLoadResult(
            snapshot: decoded.snapshot,
            recoveredFromBackup: true,
            migratedFromSchemaVersion: decoded.schemaVersion
                < WorkspaceSchema.current
                ? decoded.schemaVersion
                : nil
        )
    }

    private func decodePublishPreparationData(
        _ data: Data,
        expectedProjectID: UUID
    ) throws -> (
        snapshot: PublishPreparationSnapshot,
        schemaVersion: Int
    ) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let snapshot: PublishPreparationSnapshot
        let schemaVersion: Int

        if let rawVersion = dictionary["schemaVersion"] {
            guard let version = rawVersion as? Int,
                  version > 0 else {
                throw PublishPreparationMigrationError
                    .invalidSchemaVersion((rawVersion as? Int) ?? 0)
            }
            guard version <= PublishPreparationSchema.current else {
                throw PublishPreparationMigrationError
                    .unsupportedFutureSchemaVersion(version)
            }
            let envelope = try decoder.decode(
                PublishPreparationEnvelope.self,
                from: data
            )
            snapshot = envelope.snapshot
            schemaVersion = envelope.schemaVersion
        } else {
            snapshot = try decoder.decode(
                PublishPreparationSnapshot.self,
                from: data
            )
            schemaVersion = PublishPreparationSchema.legacyUnversioned
        }

        guard snapshot.package.projectID == expectedProjectID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (snapshot, schemaVersion)
    }

    private func decodeWorkspaceData(
        _ data: Data,
        expectedProjectID: UUID
    ) throws -> (
        snapshot: StudioWorkspaceSnapshot,
        schemaVersion: Int
    ) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let snapshot: StudioWorkspaceSnapshot
        let schemaVersion: Int

        if let rawVersion = dictionary["schemaVersion"] {
            guard let version = rawVersion as? Int,
                  version > 0 else {
                throw WorkspaceMigrationError.invalidSchemaVersion(
                    (rawVersion as? Int) ?? 0
                )
            }
            guard version <= WorkspaceSchema.current else {
                throw WorkspaceMigrationError
                    .unsupportedFutureSchemaVersion(version)
            }
            let envelope = try decoder.decode(
                StudioWorkspaceEnvelope.self,
                from: data
            )
            snapshot = envelope.snapshot
            schemaVersion = envelope.schemaVersion
        } else {
            snapshot = try decoder.decode(
                StudioWorkspaceSnapshot.self,
                from: data
            )
            schemaVersion = WorkspaceSchema.legacyUnversioned
        }

        guard snapshot.projectID == expectedProjectID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (snapshot, schemaVersion)
    }
}
