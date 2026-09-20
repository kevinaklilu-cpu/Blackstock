import Foundation

public enum ProductionMediaAuthorization: String, Codable, Sendable, CaseIterable {
    case owned
    case licensed
    case explicitlyAuthorized
    case userDeclaredResponsibility
    case unknown
    case prohibited
}

public struct WorkspaceRightsAttestation: Codable, Sendable, Equatable {
    public let channelID: String
    public let confirmedByUser: Bool
    public let attestedAt: Date
    public let statementVersion: String

    public init(
        channelID: String,
        confirmedByUser: Bool,
        attestedAt: Date,
        statementVersion: String = "workspace-rights-responsibility-v1"
    ) {
        self.channelID = channelID
        self.confirmedByUser = confirmedByUser
        self.attestedAt = attestedAt
        self.statementVersion = statementVersion
    }

    public var permitsUserDirectedProduction: Bool {
        confirmedByUser
            && !channelID.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }
}

public struct RightsAttestation: Codable, Sendable, Equatable {
    public let confirmedByUser: Bool
    public let attestedAt: Date
    public let statementVersion: String

    public init(
        confirmedByUser: Bool,
        attestedAt: Date,
        statementVersion: String = "rights-attestation-v1"
    ) {
        self.confirmedByUser = confirmedByUser
        self.attestedAt = attestedAt
        self.statementVersion = statementVersion
    }
}

public struct ProductionMediaAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let sourceURL: URL
    public let durationSeconds: Double
    public let authorization: ProductionMediaAuthorization
    public let rightsEvidence: [String]
    public let rightsAttestation: RightsAttestation
    public let originSource: MediaSourceReference?
    public let importedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        sourceURL: URL,
        durationSeconds: Double,
        authorization: ProductionMediaAuthorization,
        rightsEvidence: [String],
        rightsAttestation: RightsAttestation,
        originSource: MediaSourceReference? = nil,
        importedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.durationSeconds = max(0, durationSeconds)
        self.authorization = authorization
        self.rightsEvidence = rightsEvidence
        self.rightsAttestation = rightsAttestation
        self.originSource = originSource
        self.importedAt = importedAt
    }

    public var mayEnterProduction: Bool {
        switch authorization {
        case .owned, .licensed, .explicitlyAuthorized,
                .userDeclaredResponsibility:
            return rightsAttestation.confirmedByUser && !rightsEvidence.isEmpty
        case .unknown, .prohibited:
            return false
        }
    }
}

public struct EditTimeRange: Codable, Sendable, Equatable {
    public let startSeconds: Double
    public let durationSeconds: Double

    public init(startSeconds: Double, durationSeconds: Double) {
        self.startSeconds = max(0, startSeconds)
        self.durationSeconds = max(0, durationSeconds)
    }

    public var endSeconds: Double { startSeconds + durationSeconds }
}

public enum ReframeAspectRatio: String, Codable, Sendable, CaseIterable, Hashable {
    case landscape16x9 = "16:9"
    case portrait9x16 = "9:16"
    case square1x1 = "1:1"

    public var ratio: Double {
        switch self {
        case .landscape16x9: return 16.0 / 9.0
        case .portrait9x16: return 9.0 / 16.0
        case .square1x1: return 1.0
        }
    }

    public var germanTitle: String {
        switch self {
        case .landscape16x9: return "16:9 Querformat"
        case .portrait9x16: return "9:16 Hochformat"
        case .square1x1: return "1:1 Quadrat"
        }
    }
}

public struct ReframeSpec: Codable, Sendable, Equatable {
    public let aspectRatio: ReframeAspectRatio
    public let focalX: Double
    public let focalY: Double

    public init(
        aspectRatio: ReframeAspectRatio,
        focalX: Double = 0.5,
        focalY: Double = 0.5
    ) {
        self.aspectRatio = aspectRatio
        self.focalX = min(max(focalX, 0), 1)
        self.focalY = min(max(focalY, 0), 1)
    }
}

public struct ReframeCropPlan: Codable, Sendable, Equatable {
    public let sourceWidth: Double
    public let sourceHeight: Double
    public let cropX: Double
    public let cropY: Double
    public let cropWidth: Double
    public let cropHeight: Double

    public init(
        sourceWidth: Double,
        sourceHeight: Double,
        cropX: Double,
        cropY: Double,
        cropWidth: Double,
        cropHeight: Double
    ) {
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.cropX = cropX
        self.cropY = cropY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
    }

    public static func make(
        sourceWidth: Double,
        sourceHeight: Double,
        spec: ReframeSpec
    ) -> ReframeCropPlan? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let sourceRatio = sourceWidth / sourceHeight
        let targetRatio = spec.aspectRatio.ratio

        if sourceRatio > targetRatio {
            let cropHeight = sourceHeight
            let cropWidth = cropHeight * targetRatio
            let maxX = max(sourceWidth - cropWidth, 0)
            return .init(
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                cropX: maxX * spec.focalX,
                cropY: 0,
                cropWidth: cropWidth,
                cropHeight: cropHeight
            )
        }

        let cropWidth = sourceWidth
        let cropHeight = cropWidth / targetRatio
        let maxY = max(sourceHeight - cropHeight, 0)
        return .init(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            cropX: 0,
            cropY: maxY * spec.focalY,
            cropWidth: cropWidth,
            cropHeight: cropHeight
        )
    }
}

public enum EditOperationType: String, Codable, Sendable {
    case trim
    case removeRange
    case reorder
    case volume
    case caption
    case crop
    case reframe
    case overlay
}

public struct EditOperation: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let type: EditOperationType
    public let timeRange: EditTimeRange?
    public let value: Double?
    public let text: String?
    public let reframeSpec: ReframeSpec?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        type: EditOperationType,
        timeRange: EditTimeRange? = nil,
        value: Double? = nil,
        text: String? = nil,
        reframeSpec: ReframeSpec? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.timeRange = timeRange
        self.value = value
        self.text = text
        self.reframeSpec = reframeSpec
        self.createdAt = createdAt
    }
}

public enum EditRevisionActor: String, Codable, Sendable {
    case user
    case acceptedAIProposal
}

public struct EditRevision: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let parentID: UUID?
    public let actor: EditRevisionActor
    public let operation: EditOperation?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        parentID: UUID?,
        actor: EditRevisionActor,
        operation: EditOperation?,
        createdAt: Date
    ) {
        self.id = id
        self.parentID = parentID
        self.actor = actor
        self.operation = operation
        self.createdAt = createdAt
    }
}

public struct EditGraph: Codable, Sendable, Equatable {
    public private(set) var revisions: [EditRevision]
    public private(set) var headID: UUID

    public init(createdAt: Date) {
        let root = EditRevision(parentID: nil, actor: .user, operation: nil, createdAt: createdAt)
        self.revisions = [root]
        self.headID = root.id
    }

    public var head: EditRevision {
        revisions.first(where: { $0.id == headID })!
    }

    public mutating func apply(
        _ operation: EditOperation,
        actor: EditRevisionActor
    ) -> EditRevision {
        let revision = EditRevision(
            parentID: headID,
            actor: actor,
            operation: operation,
            createdAt: operation.createdAt
        )
        revisions.append(revision)
        headID = revision.id
        return revision
    }

    @discardableResult
    public mutating func undo() -> EditRevision? {
        guard let parentID = head.parentID,
              let parent = revisions.first(where: { $0.id == parentID }) else { return nil }
        headID = parent.id
        return parent
    }

    @discardableResult
    public mutating func redo(to revisionID: UUID) -> EditRevision? {
        guard let candidate = revisions.first(where: { $0.id == revisionID }),
              candidate.parentID == headID else { return nil }
        headID = candidate.id
        return candidate
    }

    public var currentOperations: [EditOperation] {
        var chain: [EditOperation] = []
        var cursor: EditRevision? = head
        while let revision = cursor {
            if let operation = revision.operation { chain.append(operation) }
            guard let parentID = revision.parentID else { break }
            cursor = revisions.first(where: { $0.id == parentID })
        }
        return chain.reversed()
    }
}

public struct EditTimelinePlan: Sendable, Equatable {
    public let sourceRanges: [EditTimeRange]

    public init(sourceRanges: [EditTimeRange]) {
        self.sourceRanges = sourceRanges
    }

    public var outputDurationSeconds: Double {
        sourceRanges.reduce(0) { $0 + $1.durationSeconds }
    }

    public var hasContent: Bool {
        outputDurationSeconds > 0.001
    }
}

public struct EditTimelineResolver: Sendable {
    public init() {}

    public func resolve(
        sourceDurationSeconds: Double,
        operations: [EditOperation]
    ) -> EditTimelinePlan {
        let sourceDuration = max(sourceDurationSeconds, 0)
        guard sourceDuration > 0.001 else {
            return EditTimelinePlan(sourceRanges: [])
        }

        let trim = operations
            .last(where: { $0.type == .trim })?
            .timeRange
        let baseStart = min(
            max(trim?.startSeconds ?? 0, 0),
            sourceDuration
        )
        let requestedEnd = trim?.endSeconds ?? sourceDuration
        let baseEnd = min(
            max(requestedEnd, baseStart),
            sourceDuration
        )
        guard baseEnd - baseStart > 0.001 else {
            return EditTimelinePlan(sourceRanges: [])
        }

        let removals = operations
            .filter { $0.type == .removeRange }
            .compactMap(\.timeRange)
            .compactMap { range -> EditTimeRange? in
                let start = max(range.startSeconds, baseStart)
                let end = min(range.endSeconds, baseEnd)
                guard end - start > 0.001 else { return nil }
                return EditTimeRange(
                    startSeconds: start,
                    durationSeconds: end - start
                )
            }
            .sorted { $0.startSeconds < $1.startSeconds }

        var merged: [EditTimeRange] = []
        for range in removals {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }
            if range.startSeconds <= last.endSeconds + 0.001 {
                let end = max(last.endSeconds, range.endSeconds)
                merged[merged.count - 1] = EditTimeRange(
                    startSeconds: last.startSeconds,
                    durationSeconds: end - last.startSeconds
                )
            } else {
                merged.append(range)
            }
        }

        var kept: [EditTimeRange] = []
        var cursor = baseStart
        for removal in merged {
            if removal.startSeconds - cursor > 0.001 {
                kept.append(
                    EditTimeRange(
                        startSeconds: cursor,
                        durationSeconds: removal.startSeconds - cursor
                    )
                )
            }
            cursor = max(cursor, removal.endSeconds)
        }
        if baseEnd - cursor > 0.001 {
            kept.append(
                EditTimeRange(
                    startSeconds: cursor,
                    durationSeconds: baseEnd - cursor
                )
            )
        }

        return EditTimelinePlan(sourceRanges: kept)
    }
}


public struct EditAudioPlanner: Sendable {
    public init() {}

    public func masterVolume(
        operations: [EditOperation]
    ) -> Double {
        let proposed = operations
            .last(where: { $0.type == .volume })?
            .value
            ?? 1
        return min(max(proposed, 0), 1)
    }
}
