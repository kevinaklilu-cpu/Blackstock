import Foundation

public struct StoryboardBeat: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var purpose: String
    public var timeRange: EditTimeRange?
    public var visualDirection: String
    public var sourceReferenceIDs: [String]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        purpose: String = "",
        timeRange: EditTimeRange? = nil,
        visualDirection: String = "",
        sourceReferenceIDs: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.timeRange = timeRange
        self.visualDirection = visualDirection
        self.sourceReferenceIDs = sourceReferenceIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct StoryboardPlan: Codable, Sendable, Equatable {
    public let projectID: UUID
    public private(set) var version: Int
    public private(set) var beats: [StoryboardBeat]
    public private(set) var updatedAt: Date

    public init(
        projectID: UUID,
        version: Int = 1,
        beats: [StoryboardBeat] = [],
        updatedAt: Date
    ) {
        self.projectID = projectID
        self.version = max(version, 1)
        self.beats = beats
        self.updatedAt = updatedAt
    }

    @discardableResult
    public mutating func addBeat(
        title: String,
        timeRange: EditTimeRange? = nil,
        at date: Date
    ) -> StoryboardBeat {
        let cleanTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let beat = StoryboardBeat(
            title: cleanTitle.isEmpty
                ? "Beat \(beats.count + 1)"
                : cleanTitle,
            timeRange: timeRange,
            createdAt: date,
            updatedAt: date
        )
        beats.append(beat)
        touch(at: date)
        return beat
    }

    public mutating func updateBeat(
        id: UUID,
        title: String? = nil,
        purpose: String? = nil,
        timeRange: EditTimeRange? = nil,
        visualDirection: String? = nil,
        at date: Date
    ) -> Bool {
        guard let index = beats.firstIndex(where: { $0.id == id }) else {
            return false
        }

        if let title {
            let clean = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !clean.isEmpty {
                beats[index].title = clean
            }
        }
        if let purpose {
            beats[index].purpose = purpose
        }
        if let timeRange {
            beats[index].timeRange = timeRange
        }
        if let visualDirection {
            beats[index].visualDirection = visualDirection
        }
        beats[index].updatedAt = date
        touch(at: date)
        return true
    }

    public mutating func removeBeat(
        id: UUID,
        at date: Date
    ) -> Bool {
        guard let index = beats.firstIndex(where: { $0.id == id }) else {
            return false
        }
        beats.remove(at: index)
        touch(at: date)
        return true
    }

    public mutating func moveBeat(
        from sourceIndex: Int,
        to destinationIndex: Int,
        at date: Date
    ) -> Bool {
        guard beats.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex <= beats.count else {
            return false
        }

        let beat = beats.remove(at: sourceIndex)
        let adjusted = min(destinationIndex, beats.count)
        beats.insert(beat, at: adjusted)
        touch(at: date)
        return true
    }

    public var isReadyForEditing: Bool {
        !beats.isEmpty
        && beats.allSatisfy {
            !$0.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }
    }

    private mutating func touch(at date: Date) {
        version += 1
        updatedAt = date
    }
}
