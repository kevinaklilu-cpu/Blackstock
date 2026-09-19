import Foundation

public enum GrowthRecordStoreError: Error, Sendable, Equatable {
    case invalidRoot
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

public enum GrowthRecordStoreSchema {
    public static let legacyUnversioned = 1
    public static let current = 3
}

private struct GrowthStoreEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let value: Value
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
        try Self.writeVersioned(record, to: url)
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
        guard let decoded: (PublishedVideoRecord, Int) = try Self.readVersioned(
            PublishedVideoRecord.self,
            from: url
        ) else {
            return nil
        }
        guard decoded.0.projectID == projectID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if decoded.1 < GrowthRecordStoreSchema.current {
            try Self.writeVersioned(decoded.0, to: url)
        }
        return decoded.0
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
        try Self.writeVersioned(learning, to: url)
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
        guard let decoded: (GrowthLearningRecord, Int) = try Self.readVersioned(
            GrowthLearningRecord.self,
            from: url
        ) else {
            return nil
        }
        if decoded.1 < GrowthRecordStoreSchema.current {
            try Self.writeVersioned(decoded.0, to: url)
        }
        return decoded.0
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

    private static func writeVersioned<T: Codable & Sendable>(
        _ value: T,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        encoder.outputFormatting = [.sortedKeys]
        let envelope = GrowthStoreEnvelope(
            schemaVersion: GrowthRecordStoreSchema.current,
            value: value
        )
        let data = try encoder.encode(envelope)
        try data.write(
            to: url,
            options: [.atomic]
        )
    }

    private static func readVersioned<T: Codable & Sendable>(
        _ type: T.Type,
        from url: URL
    ) throws -> (T, Int)? {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let value = try? container.decode(String.self) {
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [
                    .withInternetDateTime,
                    .withFractionalSeconds
                ]
                if let date = fractional.date(from: value) {
                    return date
                }

                let legacy = ISO8601DateFormatter()
                legacy.formatOptions = [.withInternetDateTime]
                if let date = legacy.date(from: value) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription:
                    "Expected Unix timestamp or ISO-8601 date."
            )
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if let rawVersion = dictionary["schemaVersion"] {
            guard let version = rawVersion as? Int,
                  version > 0 else {
                throw GrowthRecordStoreError.invalidSchemaVersion(
                    (rawVersion as? Int) ?? 0
                )
            }
            guard version <= GrowthRecordStoreSchema.current else {
                throw GrowthRecordStoreError
                    .unsupportedFutureSchemaVersion(version)
            }
            let envelope = try decoder.decode(
                GrowthStoreEnvelope<T>.self,
                from: data
            )
            return (envelope.value, envelope.schemaVersion)
        }

        return (
            try decoder.decode(T.self, from: data),
            GrowthRecordStoreSchema.legacyUnversioned
        )
    }
}
