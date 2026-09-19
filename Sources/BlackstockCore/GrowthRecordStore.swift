import Foundation

public enum GrowthRecordStoreError: Error, Sendable, Equatable {
    case invalidRoot
}

public struct GrowthRecordStore: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func save(
        record: PublishedVideoRecord
    ) throws {
        let directory = try projectDirectory(
            projectID: record.projectID
        )
        let url = directory.appendingPathComponent(
            "published-video.json"
        )
        try Self.write(record, to: url)
    }

    public func loadRecord(
        projectID: UUID
    ) throws -> PublishedVideoRecord? {
        let url = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "published-video.json"
            )
        return try Self.read(
            PublishedVideoRecord.self,
            from: url
        )
    }

    public func save(
        learning: GrowthLearningRecord,
        projectID: UUID
    ) throws {
        let directory = try projectDirectory(
            projectID: projectID
        )
        let url = directory.appendingPathComponent(
            "growth-learning.json"
        )
        try Self.write(learning, to: url)
    }

    public func loadLearning(
        projectID: UUID
    ) throws -> GrowthLearningRecord? {
        let url = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "growth-learning.json"
            )
        return try Self.read(
            GrowthLearningRecord.self,
            from: url
        )
    }

    public func projectDirectory(
        projectID: UUID
    ) throws -> URL {
        let directory = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func write<T: Encodable>(
        _ value: T,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(
            to: url,
            options: [.atomic]
        )
    }

    private static func read<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) throws -> T? {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            type,
            from: data
        )
    }
}
