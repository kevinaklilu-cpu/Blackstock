import Foundation

public struct SupplementalVideoInsertSetting:
    Codable,
    Sendable,
    Equatable,
    Identifiable {

    public let captureID: UUID
    public var enabled: Bool
    public var timelineStartSeconds: Double
    public var sourceStartSeconds: Double
    public var durationSeconds: Double

    public var id: UUID { captureID }

    public init(
        captureID: UUID,
        enabled: Bool = false,
        timelineStartSeconds: Double = 0,
        sourceStartSeconds: Double = 0,
        durationSeconds: Double = 5
    ) {
        self.captureID = captureID
        self.enabled = enabled
        self.timelineStartSeconds = max(timelineStartSeconds, 0)
        self.sourceStartSeconds = max(sourceStartSeconds, 0)
        self.durationSeconds = max(durationSeconds, 0)
    }
}

public struct SupplementalVideoInsertPlan:
    Sendable,
    Equatable,
    Identifiable {

    public let captureID: UUID
    public let timelineStartSeconds: Double
    public let sourceStartSeconds: Double
    public let durationSeconds: Double

    public var id: UUID { captureID }

    public init(
        captureID: UUID,
        timelineStartSeconds: Double,
        sourceStartSeconds: Double,
        durationSeconds: Double
    ) {
        self.captureID = captureID
        self.timelineStartSeconds = max(timelineStartSeconds, 0)
        self.sourceStartSeconds = max(sourceStartSeconds, 0)
        self.durationSeconds = max(durationSeconds, 0)
    }
}

public struct SupplementalVideoInsertInput:
    Sendable,
    Equatable,
    Identifiable {

    public let captureID: UUID
    public let fileURL: URL
    public let timelineStartSeconds: Double
    public let sourceStartSeconds: Double
    public let durationSeconds: Double

    public var id: UUID { captureID }

    public init(
        captureID: UUID,
        fileURL: URL,
        timelineStartSeconds: Double,
        sourceStartSeconds: Double,
        durationSeconds: Double
    ) {
        self.captureID = captureID
        self.fileURL = fileURL
        self.timelineStartSeconds = max(timelineStartSeconds, 0)
        self.sourceStartSeconds = max(sourceStartSeconds, 0)
        self.durationSeconds = max(durationSeconds, 0)
    }
}

public struct SupplementalVideoInsertPlanner: Sendable {
    public init() {}

    public func plan(
        setting: SupplementalVideoInsertSetting,
        sourceDurationSeconds: Double,
        outputDurationSeconds: Double
    ) -> SupplementalVideoInsertPlan? {
        guard setting.enabled else { return nil }

        let sourceDuration = max(sourceDurationSeconds, 0)
        let outputDuration = max(outputDurationSeconds, 0)
        guard sourceDuration > 0.05,
              outputDuration > 0.05 else {
            return nil
        }

        let timelineStart = min(
            max(setting.timelineStartSeconds, 0),
            outputDuration
        )
        let sourceStart = min(
            max(setting.sourceStartSeconds, 0),
            sourceDuration
        )
        let duration = min(
            max(setting.durationSeconds, 0),
            outputDuration - timelineStart,
            sourceDuration - sourceStart
        )
        guard duration >= 0.05 else { return nil }

        return SupplementalVideoInsertPlan(
            captureID: setting.captureID,
            timelineStartSeconds: timelineStart,
            sourceStartSeconds: sourceStart,
            durationSeconds: duration
        )
    }
}
