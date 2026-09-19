import Foundation

public struct GrowthObservationPlan: Codable, Sendable, Equatable, Identifiable {
    public var id: String { window.rawValue }

    public let window: GrowthObservationWindow
    public let eligibleAt: Date
    public let requestedStartDate: String
    public let requestedEndDate: String
    public let temporalSemantic: TemporalSemantic
    public let alreadyCollected: Bool
    public let isDue: Bool

    public init(
        window: GrowthObservationWindow,
        eligibleAt: Date,
        requestedStartDate: String,
        requestedEndDate: String,
        temporalSemantic: TemporalSemantic = .analyticsPeriod,
        alreadyCollected: Bool,
        isDue: Bool
    ) {
        self.window = window
        self.eligibleAt = eligibleAt
        self.requestedStartDate = requestedStartDate
        self.requestedEndDate = requestedEndDate
        self.temporalSemantic = temporalSemantic
        self.alreadyCollected = alreadyCollected
        self.isDue = isDue
    }
}

public struct GrowthObservationPlanner: Sendable {
    public init() {}

    public func plans(
        for record: PublishedVideoRecord,
        now: Date
    ) -> [GrowthObservationPlan] {
        let collected = Set(record.observations.map(\.window))
        return GrowthObservationWindow.allCases.map { window in
            let eligibleAt = record.publishedAt.addingTimeInterval(
                window.elapsedSeconds
            )
            return GrowthObservationPlan(
                window: window,
                eligibleAt: eligibleAt,
                requestedStartDate: Self.analyticsDateString(
                    record.publishedAt
                ),
                requestedEndDate: Self.analyticsDateString(now),
                alreadyCollected: collected.contains(window),
                isDue: now >= eligibleAt && !collected.contains(window)
            )
        }
    }

    public func duePlans(
        for record: PublishedVideoRecord,
        now: Date
    ) -> [GrowthObservationPlan] {
        plans(for: record, now: now).filter(\.isDue)
    }

    public func nextDueAt(
        for record: PublishedVideoRecord,
        now: Date
    ) -> Date? {
        plans(for: record, now: now)
            .filter { !$0.alreadyCollected && $0.eligibleAt > now }
            .map(\.eligibleAt)
            .min()
    }

    public static func analyticsDateString(
        _ date: Date
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(
            identifier: "America/Los_Angeles"
        ) ?? .gmt

        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

public extension GrowthObservationWindow {
    var elapsedSeconds: TimeInterval {
        switch self {
        case .first24Hours:
            return 24 * 60 * 60
        case .first72Hours:
            return 72 * 60 * 60
        case .first7Days:
            return 7 * 24 * 60 * 60
        case .first28Days:
            return 28 * 24 * 60 * 60
        }
    }
}
