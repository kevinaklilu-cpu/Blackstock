import Foundation

public enum CapabilityAuthorizationState: String, Codable, Sendable {
    case authorized
    case unauthorized
    case unavailable
}

public enum CapabilityPolicyState: String, Codable, Sendable {
    case allowed
    case denied
    case unknown
}

public enum CapabilityAvailability: String, Codable, Sendable {
    case available
    case unavailable
    case unknown
}

public enum CapabilityVerificationState: String, Codable, Sendable {
    case pass
    case fail
}

public struct CapabilityRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { capabilityId }

    public let capabilityId: String
    public let provider: String
    public let implementationVersion: String
    public let authorizationState: CapabilityAuthorizationState
    public let policyState: CapabilityPolicyState
    public let regionAvailability: CapabilityAvailability
    public let channelAvailability: CapabilityAvailability
    public let requiredScopes: [String]
    public let dataAvailability: CapabilityAvailability
    public let qualityStatus: CapabilityVerificationState
    public let testStatus: CapabilityVerificationState
    public let lastVerifiedAt: Date

    public init(
        capabilityId: String,
        provider: String,
        implementationVersion: String,
        authorizationState: CapabilityAuthorizationState,
        policyState: CapabilityPolicyState,
        regionAvailability: CapabilityAvailability,
        channelAvailability: CapabilityAvailability,
        requiredScopes: [String],
        dataAvailability: CapabilityAvailability,
        qualityStatus: CapabilityVerificationState,
        testStatus: CapabilityVerificationState,
        lastVerifiedAt: Date
    ) {
        self.capabilityId = capabilityId
        self.provider = provider
        self.implementationVersion = implementationVersion
        self.authorizationState = authorizationState
        self.policyState = policyState
        self.regionAvailability = regionAvailability
        self.channelAvailability = channelAvailability
        self.requiredScopes = requiredScopes
        self.dataAvailability = dataAvailability
        self.qualityStatus = qualityStatus
        self.testStatus = testStatus
        self.lastVerifiedAt = lastVerifiedAt
    }

    public var userFacingAvailable: Bool {
        authorizationState == .authorized
        && policyState == .allowed
        && regionAvailability == .available
        && channelAvailability == .available
        && dataAvailability == .available
        && qualityStatus == .pass
        && testStatus == .pass
    }

    public func scopesSatisfied(by grantedScopes: Set<String>) -> Bool {
        Set(requiredScopes).isSubset(of: grantedScopes)
    }
}

public actor CapabilityRegistry {
    private var records: [String: CapabilityRecord]

    public init(records: [CapabilityRecord] = []) {
        self.records = Dictionary(
            uniqueKeysWithValues: records.map { ($0.capabilityId, $0) }
        )
    }

    public func upsert(_ record: CapabilityRecord) {
        records[record.capabilityId] = record
    }

    public func record(_ id: String) -> CapabilityRecord? {
        records[id]
    }

    public func isVisible(_ id: String, grantedScopes: Set<String> = []) -> Bool {
        guard let record = records[id] else { return false }
        return record.userFacingAvailable && record.scopesSatisfied(by: grantedScopes)
    }
}
