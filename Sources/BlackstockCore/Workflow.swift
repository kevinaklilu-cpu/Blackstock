import Foundation

public enum BlackstockStage: String, Codable, Sendable, CaseIterable {
    case discovery = "DISCOVERY"
    case research = "RESEARCH"
    case analysis = "ANALYSIS"
    case production = "PRODUCTION"
    case preview = "PREVIEW"
    case storyboard = "STORYBOARD"
    case editing = "EDITING"
    case packaging = "PACKAGING"
    case review = "REVIEW"
    case publishing = "PUBLISHING"
    case published = "PUBLISHED"

    public var next: BlackstockStage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), all.indices.contains(index + 1) else { return nil }
        return all[index + 1]
    }

    public func canTransition(to destination: BlackstockStage) -> Bool {
        destination == next
    }
}

public enum JobControl: String, Codable, Sendable {
    case pausable = "PAUSABLE"
    case checkpointPausable = "CHECKPOINT_PAUSABLE"
    case resumable = "RESUMABLE"
    case cancelOnly = "CANCEL_ONLY"
    case nonInterruptibleShortStep = "NON_INTERRUPTIBLE_SHORT_STEP"

    public var supportsPause: Bool {
        self == .pausable || self == .checkpointPausable
    }

    public var supportsResume: Bool {
        self == .pausable || self == .checkpointPausable || self == .resumable
    }
}

public struct StageGate: Codable, Sendable, Equatable {
    public let stage: BlackstockStage
    public let checks: [String: Bool]

    public init(stage: BlackstockStage, checks: [String: Bool]) {
        self.stage = stage
        self.checks = checks
    }

    public var passes: Bool {
        !checks.isEmpty && checks.values.allSatisfy { $0 }
    }

    public var failingChecks: [String] {
        checks.filter { !$0.value }.map(\.key).sorted()
    }
}
