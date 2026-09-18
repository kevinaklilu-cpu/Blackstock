import Foundation

public enum RightsState: String, Codable, Sendable { case unknown, owned, licensed, authorized, prohibited }
public enum TemporalSemantic: String, Codable, Sendable {
    case publishedInWindow = "PUBLISHED_IN_WINDOW"
    case observedInWindow = "OBSERVED_IN_WINDOW"
    case analyticsPeriod = "ANALYTICS_PERIOD"
    case externalTrendPeriod = "EXTERNAL_TREND_PERIOD"
}

public enum ActionRiskClass: String, Codable, Sendable {
    case readOnly = "READ_ONLY"
    case localDraft = "LOCAL_DRAFT"
    case localReversible = "LOCAL_REVERSIBLE"
    case remoteReversible = "REMOTE_REVERSIBLE"
    case remoteHighImpact = "REMOTE_HIGH_IMPACT"
}

public struct ActionAuthorization: Sendable, Equatable {
    public let riskClass: ActionRiskClass
    public let deterministicChecksPassed: Bool
    public let userConfirmed: Bool
    public var mayExecute: Bool {
        guard deterministicChecksPassed else { return false }
        return riskClass == .remoteHighImpact ? userConfirmed : true
    }
}

public enum PublicationPreflightError: Error, Equatable, Sendable {
    case missingTargetChannel, wrongChannel, renderNotValidated, rightsNotValidated, authorizationMissing, quotaUnavailable, networkUnavailable
}

public struct PublicationPreflightContext: Sendable, Equatable {
    public let projectTargetChannelID: String?
    public let workspaceChannelID: String
    public let authorizedUploadChannelID: String
    public let renderValidated: Bool
    public let rightsValidated: Bool
    public let authorizationAvailable: Bool
    public let quotaAvailable: Bool
    public let networkAvailable: Bool
    public func validate() throws {
        guard let target = projectTargetChannelID, !target.isEmpty else { throw PublicationPreflightError.missingTargetChannel }
        guard target == workspaceChannelID, target == authorizedUploadChannelID else { throw PublicationPreflightError.wrongChannel }
        guard renderValidated else { throw PublicationPreflightError.renderNotValidated }
        guard rightsValidated else { throw PublicationPreflightError.rightsNotValidated }
        guard authorizationAvailable else { throw PublicationPreflightError.authorizationMissing }
        guard quotaAvailable else { throw PublicationPreflightError.quotaUnavailable }
        guard networkAvailable else { throw PublicationPreflightError.networkUnavailable }
    }
}