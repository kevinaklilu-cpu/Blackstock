import Foundation

public enum GrowthRecordStoreError: Error, Sendable, Equatable {
    case invalidRoot
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

public enum GrowthRecordStoreSchema {
    public static let legacyUnversioned = 1
    public static let current = 2
}

private struct GrowthStoreEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let value: Value
}

public struct GrowthStoreLoadResult<Value: Codable & Sendable & Equatable>: Sendable, Equatable {
    public let value: Value?
    public let recoveredFromBackup: Bool
    public let migratedFromSchemaVersion: Int?

    public init(
        value: Value?,
        recoveredFromBackup: Bool,
        migratedFromSchemaVersion: Int? = nil
    ) {
        self.value = value
        self.recoveredFromBackup = recoveredFromBackup
        self.migratedFromSchemaVersion = migratedFromSchemaVersion
    }
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
        try Self.writeVersionedWithBackup(
            record,
            primaryURL: url
        )
    }

    public func loadRecord(
        projectID: UUID
    ) throws -> PublishedVideoRecord? {
        try loadRecordWithRecovery(
            projectID: projectID
        ).value
    }

    public func loadRecordWithRecovery(
        projectID: UUID
    ) throws -> GrowthStoreLoadResult<PublishedVideoRecord> {
        let url = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "published-video.json"
            )
        let result = try Self.readVersionedWithRecovery(
            PublishedVideoRecord.self,
            primaryURL: url
        )
        guard let record = result.value else {
            return result
        }
        guard record.projectID == projectID else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let migrated = result.migratedFromSchemaVersion,
           migrated < GrowthRecordStoreSchema.current {
            try Self.writeVersionedWithBackup(
                record,
                primaryURL: url
            )
        }
        return result
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
        try Self.writeVersionedWithBackup(
            learning,
            primaryURL: url
        )
    }

    public func loadLearning(
        projectID: UUID
    ) throws -> GrowthLearningRecord? {
        try loadLearningWithRecovery(
            projectID: projectID
        ).value
    }

    public func loadLearningWithRecovery(
        projectID: UUID
    ) throws -> GrowthStoreLoadResult<GrowthLearningRecord> {
        let url = rootURL
            .appendingPathComponent(
                projectID.uuidString,
                isDirectory: true
            )
            .appendingPathComponent(
                "growth-learning.json"
            )
        let result = try Self.readVersionedWithRecovery(
            GrowthLearningRecord.self,
            primaryURL: url
        )
        if let learning = result.value,
           let migrated = result.migratedFromSchemaVersion,
           migrated < GrowthRecordStoreSchema.current {
            try Self.writeVersionedWithBackup(
                learning,
                primaryURL: url
            )
        }
        return result
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

    private static func backupURL(
        for primaryURL: URL
    ) -> URL {
        let basename = primaryURL
            .deletingPathExtension()
            .lastPathComponent
        return primaryURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                basename + ".backup.json"
            )
    }

    private static func writeVersionedWithBackup<T: Codable & Sendable>(
        _ value: T,
        primaryURL: URL
    ) throws {
        let backup = backupURL(for: primaryURL)
        if FileManager.default.fileExists(
            atPath: primaryURL.path
        ),
           let primaryData = try? Data(
                contentsOf: primaryURL
           ),
           (try? decodeVersioned(
                T.self,
                data: primaryData
           )) != nil {
            try primaryData.write(
                to: backup,
                options: [.atomic]
            )
        }
        try writeVersioned(value, to: primaryURL)
    }

    private static func readVersionedWithRecovery<
        T: Codable & Sendable & Equatable
    >(
        _ type: T.Type,
        primaryURL: URL
    ) throws -> GrowthStoreLoadResult<T> {
        let backup = backupURL(for: primaryURL)
        let primaryExists = FileManager.default.fileExists(
            atPath: primaryURL.path
        )
        let backupExists = FileManager.default.fileExists(
            atPath: backup.path
        )
        guard primaryExists || backupExists else {
            return GrowthStoreLoadResult(
                value: nil,
                recoveredFromBackup: false
            )
        }

        if primaryExists {
            do {
                let data = try Data(contentsOf: primaryURL)
                let decoded: (T, Int) = try decodeVersioned(
                    T.self,
                    data: data
                )
                return GrowthStoreLoadResult(
                    value: decoded.0,
                    recoveredFromBackup: false,
                    migratedFromSchemaVersion:
                        decoded.1
                        < GrowthRecordStoreSchema.current
                        ? decoded.1
                        : nil
                )
            } catch {
                guard backupExists else {
                    throw error
                }
            }
        }

        let backupData = try Data(contentsOf: backup)
        let decoded: (T, Int) = try decodeVersioned(
            T.self,
            data: backupData
        )
        return GrowthStoreLoadResult(
            value: decoded.0,
            recoveredFromBackup: true,
            migratedFromSchemaVersion:
                decoded.1
                < GrowthRecordStoreSchema.current
                ? decoded.1
                : nil
        )
    }

    private static func writeVersioned<T: Codable & Sendable>(
        _ value: T,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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

    private static func decodeVersioned<T: Codable & Sendable>(
        _ type: T.Type,
        data: Data
    ) throws -> (T, Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(
            with: data
        )
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
            return (
                envelope.value,
                envelope.schemaVersion
            )
        }

        return (
            try decoder.decode(T.self, from: data),
            GrowthRecordStoreSchema.legacyUnversioned
        )
    }
}
