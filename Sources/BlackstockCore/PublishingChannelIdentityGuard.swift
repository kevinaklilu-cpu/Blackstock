import Foundation

public enum PublishingChannelIdentityValidationError: Error, Sendable, Equatable {
    case noAuthorizedChannel
    case ambiguousAuthorizedChannels
    case targetChannelMismatch
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
