import Foundation

public enum CapabilityAuthorizationState: String, Codable, Sendable { case authorized, unauthorized, unavailable }
public enum CapabilityPolicyState: String, Codable, Sendable { case allowed, denied, unknown }
public enum CapabilityAvailability: String, Codable, Sendable { case available, unavailable, unknown }
public enum CapabilityVerificationState: String, Codable, Sendable { case pass, fail }

public struct CapabilityRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { capabilityID }
    public let capabilityID: String
    public let provider: String
    public let implementationVersion: String
    public let authorization: CapabilityAuthorizationState
    public let policy: CapabilityPolicyState
    public let region: CapabilityAvailability
    public let channel: CapabilityAvailability
    public let data: CapabilityAvailability
    public let quality: CapabilityVerificationState
    public let tests: CapabilityVerificationState
    public let lastVerifiedAt: Date

    public var userFacingAvailable: Bool {
        authorization == .authorized && policy == .allowed && region == .available &&
        channel == .available && data == .available && quality == .pass && tests == .pass
    }
}

public actor CapabilityRegistry {
    private var records: [String: CapabilityRecord]
    public init(records: [CapabilityRecord] = []) { self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.capabilityID, $0) }) }
    public func upsert(_ record: CapabilityRecord) { records[record.capabilityID] = record }
    public func record(_ id: String) -> CapabilityRecord? { records[id] }
    public func isVisible(_ id: String) -> Bool { records[id]?.userFacingAvailable == true }
}