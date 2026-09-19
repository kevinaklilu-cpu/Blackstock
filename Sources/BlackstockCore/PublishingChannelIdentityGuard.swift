import Foundation

public enum PublishingChannelIdentityValidationError: Error, LocalizedError, Sendable, Equatable {
    case noAuthorizedChannel
    case ambiguousAuthorizedChannels
    case targetChannelMismatch

    public var errorDescription: String? {
        switch self {
        case .noAuthorizedChannel:
            return "Google hat keinen eindeutig autorisierten YouTube-Kanal geliefert."
        case .ambiguousAuthorizedChannels:
            return "Google hat mehrere autorisierte YouTube-Kanäle geliefert. Blackstock führt deshalb keinen Upload aus."
        case .targetChannelMismatch:
            return "Der unmittelbar autorisierte YouTube-Kanal stimmt nicht mit dem Projekt-Zielkanal überein."
        }
    }
}

public struct PublishingChannelIdentityGuard: Sendable {
    public init() {}

    @discardableResult
    public func validate(
        targetChannelID: String,
        identities: [YouTubeChannelIdentity]
    ) throws -> YouTubeChannelIdentity {
        let target = targetChannelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !identities.isEmpty else {
            throw PublishingChannelIdentityValidationError.noAuthorizedChannel
        }
        guard identities.count == 1 else {
            throw PublishingChannelIdentityValidationError.ambiguousAuthorizedChannels
        }
        let identity = identities[0]
        guard !target.isEmpty, identity.id == target else {
            throw PublishingChannelIdentityValidationError.targetChannelMismatch
        }
        return identity
    }
}
