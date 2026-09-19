import Foundation

public struct OpportunityProjectSeed: Sendable, Equatable {
    public let project: BlackstockProject
    public let source: MediaSourceReference
    public let opportunityID: String

    public init(
        project: BlackstockProject,
        source: MediaSourceReference,
        opportunityID: String
    ) {
        self.project = project
        self.source = source
        self.opportunityID = opportunityID
    }
}

public enum OpportunityProjectFactoryError: Error, Sendable, Equatable {
    case missingTargetChannel
    case channelMismatch
    case invalidVideoID
}

public struct OpportunityProjectFactory: Sendable {
    public init() {}

    public func make(
        opportunity: YouTubeOpportunityCandidate,
        targetChannelID: String,
        strategyVersion: Int,
        now: Date = Date()
    ) throws -> OpportunityProjectSeed {
        let channel = targetChannelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !channel.isEmpty else {
            throw OpportunityProjectFactoryError.missingTargetChannel
        }

        let videoID = opportunity.videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else {
            throw OpportunityProjectFactoryError.invalidVideoID
        }

        let project = BlackstockProject(
            title: opportunity.title,
            targetChannelID: channel,
            stage: .research,
            strategyVersion: max(strategyVersion, 1),
            createdAt: now,
            updatedAt: now
        )

        let source = MediaSourceReference(
            provider: .youtube,
            pageURL: URL(string: "https://www.youtube.com/watch?v=\(videoID)")!,
            externalID: videoID,
            discoveredAt: opportunity.retrievedAt
        )

        return .init(
            project: project,
            source: source,
            opportunityID: opportunity.id
        )
    }
}
