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

public enum ProjectPackagingAssetKind: String, Codable, Sendable {
    case thumbnail = "Thumbnails"
    case caption = "Captions"
}

public struct WorkspaceLoadResult: Sendable, Equatable {
    public let snapshot: StudioWorkspaceSnapshot?
    public let recoveredFromBackup: Bool

    public init(
        snapshot: StudioWorkspaceSnapshot?,
        recoveredFromBackup: Bool
    ) {
        self.snapshot = snapshot
        self.recoveredFromBackup = recoveredFromBackup
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
        let data = try encoder.encode(snapshot)
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            PublishPreparationSnapshot.self,
            from: data
        )
        guard snapshot.package.projectID == projectID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return snapshot
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        if FileManager.default.fileExists(atPath: primaryURL.path),
           let primaryData = try? Data(contentsOf: primaryURL),
           let primarySnapshot = try? decodeWorkspaceSnapshot(
                primaryData,
                expectedProjectID: snapshot.projectID
           ) {
            let backupData = try encoder.encode(primarySnapshot)
            try backupData.write(to: backupURL, options: [.atomic])
        }

        let data = try encoder.encode(snapshot)
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
                let snapshot = try decodeWorkspaceSnapshot(
                    data,
                    expectedProjectID: projectID
                )
                return WorkspaceLoadResult(
                    snapshot: snapshot,
                    recoveredFromBackup: false
                )
            } catch {
                guard backupExists else { throw error }
            }
        }

        let backupData = try Data(contentsOf: backupURL)
        let recovered = try decodeWorkspaceSnapshot(
            backupData,
            expectedProjectID: projectID
        )
        return WorkspaceLoadResult(
            snapshot: recovered,
            recoveredFromBackup: true
        )
    }

    private func decodeWorkspaceSnapshot(
        _ data: Data,
        expectedProjectID: UUID
    ) throws -> StudioWorkspaceSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            StudioWorkspaceSnapshot.self,
            from: data
        )
        guard snapshot.projectID == expectedProjectID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return snapshot
    }
}
