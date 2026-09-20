import Foundation

public enum ProjectProductionIntentKind: String, Codable, Sendable, Equatable {
    case standardProject = "STANDARD_PROJECT"
    case clipFromOpportunity = "CLIP_FROM_OPPORTUNITY"
}

public struct ProjectProductionIntent: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let sourceID: UUID
    public let kind: ProjectProductionIntentKind
    public let createdAt: Date

    public init(
        projectID: UUID,
        sourceID: UUID,
        kind: ProjectProductionIntentKind,
        createdAt: Date
    ) {
        self.projectID = projectID
        self.sourceID = sourceID
        self.kind = kind
        self.createdAt = createdAt
    }

    public var isLinkFirstClip: Bool {
        kind == .clipFromOpportunity
    }
}
