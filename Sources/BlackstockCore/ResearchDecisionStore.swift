import Foundation

public enum ResearchDecisionStoreError: Error, Sendable, Equatable {
    case invalidRoot
    case projectMismatch
    case unsupportedFutureSchemaVersion(Int)
}

public struct ResearchEvidenceRecord: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let opportunityID: String
    public let source: MediaSourceReference
    public let researchQuestion: String
    public let providerFacts: [String]
    public let creatorNotes: String
    public let createdAt: Date

    public init(
        projectID: UUID,
        opportunityID: String,
        source: MediaSourceReference,
        researchQuestion: String,
        providerFacts: [String],
        creatorNotes: String,
        createdAt: Date
    ) {
        self.projectID = projectID
        self.opportunityID = opportunityID
        self.source = source
        self.researchQuestion = researchQuestion
        self.providerFacts = providerFacts
        self.creatorNotes = creatorNotes
        self.createdAt = createdAt
    }

    public var isComplete: Bool {
        !researchQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !providerFacts.isEmpty
        && !creatorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum ProductionDecision: String, Codable, Sendable, Equatable, CaseIterable {
    case pursue
    case reject
}

public struct AnalysisDecisionRecord: Codable, Sendable, Equatable {
    public let projectID: UUID
    public let decision: ProductionDecision
    public let rationale: String
    public let riskOrUnknown: String
    public let createdAt: Date

    public init(
        projectID: UUID,
        decision: ProductionDecision,
        rationale: String,
        riskOrUnknown: String,
        createdAt: Date
    ) {
        self.projectID = projectID
        self.decision = decision
        self.rationale = rationale
        self.riskOrUnknown = riskOrUnknown
        self.createdAt = createdAt
    }

    public var isComplete: Bool {
        !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !riskOrUnknown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ResearchEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let value: Value
}

public struct ResearchDecisionStore: Sendable {
    public static let currentSchemaVersion = 1
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func deleteProject(
        projectID: UUID
    ) throws {
        let directory = rootURL.appendingPathComponent(
            projectID.uuidString,
            isDirectory: true
        )
        if FileManager.default.fileExists(
            atPath: directory.path
        ) {
            try FileManager.default.removeItem(
                at: directory
            )
        }
    }

    public func saveResearch(_ record: ResearchEvidenceRecord) throws {
        try save(
            record,
            projectID: record.projectID,
            fileName: "research.json"
        )
    }

    public func loadResearch(
        projectID: UUID
    ) throws -> ResearchEvidenceRecord? {
        try load(
            ResearchEvidenceRecord.self,
            projectID: projectID,
            fileName: "research.json"
        )
    }

    public func saveAnalysis(_ record: AnalysisDecisionRecord) throws {
        try save(
            record,
            projectID: record.projectID,
            fileName: "analysis.json"
        )
    }

    public func loadAnalysis(
        projectID: UUID
    ) throws -> AnalysisDecisionRecord? {
        try load(
            AnalysisDecisionRecord.self,
            projectID: projectID,
            fileName: "analysis.json"
        )
    }

    private func directory(projectID: UUID) throws -> URL {
        guard rootURL.isFileURL else {
            throw ResearchDecisionStoreError.invalidRoot
        }
        let directory = rootURL.appendingPathComponent(
            projectID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func save<T: Codable & Sendable>(
        _ value: T,
        projectID: UUID,
        fileName: String
    ) throws {
        let url = try directory(projectID: projectID)
            .appendingPathComponent(fileName)
        let envelope = ResearchEnvelope(
            schemaVersion: Self.currentSchemaVersion,
            value: value
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(
            to: url,
            options: [.atomic]
        )
    }

    private func load<T: Codable & Sendable>(
        _ type: T.Type,
        projectID: UUID,
        fileName: String
    ) throws -> T? {
        let url = try directory(projectID: projectID)
            .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            ResearchEnvelope<T>.self,
            from: data
        )
        guard envelope.schemaVersion <= Self.currentSchemaVersion else {
            throw ResearchDecisionStoreError.unsupportedFutureSchemaVersion(
                envelope.schemaVersion
            )
        }

        if let research = envelope.value as? ResearchEvidenceRecord,
           research.projectID != projectID {
            throw ResearchDecisionStoreError.projectMismatch
        }
        if let analysis = envelope.value as? AnalysisDecisionRecord,
           analysis.projectID != projectID {
            throw ResearchDecisionStoreError.projectMismatch
        }
        return envelope.value
    }
}
