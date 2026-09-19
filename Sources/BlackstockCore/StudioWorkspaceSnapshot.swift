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
        let url = directory.appendingPathComponent(
            "studio-workspace.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    public func load(
        projectID: UUID
    ) throws -> StudioWorkspaceSnapshot? {
        let url = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "studio-workspace.json"
            )

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            StudioWorkspaceSnapshot.self,
            from: data
        )
    }
}
