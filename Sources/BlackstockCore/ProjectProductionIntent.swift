import Foundation

public enum ProjectProductionIntentKind: String, Codable, Sendable, Equatable {
    case standardProject = "STANDARD_PROJECT"
    case clipFromOpportunity = "CLIP_FROM_OPPORTUNITY"
}

public struct ProjectProductionIntent: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let sourceID: UUID
    public let kind: ProjectProductionIntentKind
    public let channelCategoryID: String?
    public let channelCategoryTitle: String?
    public let regionCode: String?
    public let contentLanguage: String?
    public let createdAt: Date

    public init(
        projectID: UUID,
        sourceID: UUID,
        kind: ProjectProductionIntentKind,
        channelCategoryID: String? = nil,
        channelCategoryTitle: String? = nil,
        regionCode: String? = nil,
        contentLanguage: String? = nil,
        createdAt: Date
    ) {
        self.projectID = projectID
        self.sourceID = sourceID
        self.kind = kind
        self.channelCategoryID = channelCategoryID
        self.channelCategoryTitle = channelCategoryTitle
        self.regionCode = regionCode
        self.contentLanguage = contentLanguage
        self.createdAt = createdAt
    }

    public var isLinkFirstClip: Bool {
        kind == .clipFromOpportunity
    }
}
