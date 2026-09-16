import Foundation

public struct ReleasePackageManifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let product: String
    public let projectID: UUID
    public let title: String
    public let description: String
    public let tags: [String]
    public let targetFormat: VideoFormat
    public let renderCanvas: RenderCanvas
    public let videoFileName: String
    public let thumbnailFileName: String
    public let createdAt: Date

    public init(
        schemaVersion: Int = 1,
        product: String = "Blackstock",
        projectID: UUID,
        title: String,
        description: String,
        tags: [String],
        targetFormat: VideoFormat,
        renderCanvas: RenderCanvas,
        videoFileName: String,
        thumbnailFileName: String,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.projectID = projectID
        self.title = title
        self.description = description
        self.tags = tags
        self.targetFormat = targetFormat
        self.renderCanvas = renderCanvas
        self.videoFileName = videoFileName
        self.thumbnailFileName = thumbnailFileName
        self.createdAt = createdAt
    }
}

public enum ReleasePackageError: LocalizedError, Equatable {
    case notReady([String])
    public var errorDescription: String? {
        switch self {
        case .notReady(let missing): return "Release-Paket unvollständig: " + missing.joined(separator: ", ")
        }
    }
}

public struct ReleasePackageBuilder: Sendable {
    public init() {}

    public func manifest(for project: Project, createdAt: Date = Date()) throws -> ReleasePackageManifest {
        let missing = ProjectWorkflowEngine().readiness(for: project).filter { !$0.isComplete }.map(\.label)
        guard missing.isEmpty else { throw ReleasePackageError.notReady(missing) }
        guard let video = project.renderedOutputURL, let thumbnail = project.thumbnailURL else {
            throw ReleasePackageError.notReady(["Video oder Thumbnail fehlt"])
        }
        return ReleasePackageManifest(
            projectID: project.id,
            title: (project.publishTitle ?? project.title).trimmingCharacters(in: .whitespacesAndNewlines),
            description: (project.publishDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            tags: project.publishTags ?? [],
            targetFormat: project.targetFormat,
            renderCanvas: project.effectiveRenderCanvas,
            videoFileName: video.lastPathComponent,
            thumbnailFileName: thumbnail.lastPathComponent,
            createdAt: createdAt
        )
    }
}
