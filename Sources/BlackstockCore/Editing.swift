import Foundation

public enum ProductionMediaAuthorization: String, Codable, Sendable {
    case owned
    case licensed
    case explicitlyAuthorized
    case unknown
    case prohibited
}

public struct ProductionMediaAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let sourceURL: URL
    public let durationSeconds: Double
    public let authorization: ProductionMediaAuthorization
    public let rightsEvidence: [String]
    public let importedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        sourceURL: URL,
        durationSeconds: Double,
        authorization: ProductionMediaAuthorization,
        rightsEvidence: [String],
        importedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.durationSeconds = max(0, durationSeconds)
        self.authorization = authorization
        self.rightsEvidence = rightsEvidence
        self.importedAt = importedAt
    }

    public var mayEnterProduction: Bool {
        switch authorization {
        case .owned, .licensed, .explicitlyAuthorized:
            return !rightsEvidence.isEmpty
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
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        type: EditOperationType,
        timeRange: EditTimeRange? = nil,
        value: Double? = nil,
        text: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.timeRange = timeRange
        self.value = value
        self.text = text
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
