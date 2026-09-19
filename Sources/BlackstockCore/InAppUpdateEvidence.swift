import Foundation

public enum InAppUpdateEvidenceError:
    Error,
    Sendable,
    Equatable {
    case evidenceMissing
    case manifestMismatch
    case packageNotVerified
    case installerNotOpened
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

public enum InAppUpdateEvidenceSchema {
    public static let current = 1
}

public struct InAppUpdateEvidence:
    Codable,
    Sendable,
    Equatable {
    public let id: UUID
    public let currentVersion: String
    public let currentBuild: Int
    public let manifestURL: URL
    public let expectedInstallerTeamID: String
    public let startedAt: Date

    public var targetVersion: String?
    public var targetBuild: Int?
    public var packageURL: URL?
    public var packageSHA256: String?
    public var manifestVerifiedAt: Date?
    public var packageIntegrityVerifiedAt: Date?
    public var installerTeamVerifiedAt: Date?
    public var installerOpenedAt: Date?
    public var observedInstalledVersion: String?
    public var observedInstalledBuild: Int?
    public var postUpdateLaunchVerifiedAt: Date?

    public init(
        id: UUID = UUID(),
        currentVersion: String,
        currentBuild: Int,
        manifestURL: URL,
        expectedInstallerTeamID: String,
        startedAt: Date
    ) {
        self.id = id
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.manifestURL = manifestURL
        self.expectedInstallerTeamID =
            expectedInstallerTeamID
        self.startedAt = startedAt
        targetVersion = nil
        targetBuild = nil
        packageURL = nil
        packageSHA256 = nil
        manifestVerifiedAt = nil
        packageIntegrityVerifiedAt = nil
        installerTeamVerifiedAt = nil
        installerOpenedAt = nil
        observedInstalledVersion = nil
        observedInstalledBuild = nil
        postUpdateLaunchVerifiedAt = nil
    }

    public var hasVerifiedManifest: Bool {
        targetVersion != nil
            && targetBuild != nil
            && packageURL != nil
            && packageSHA256 != nil
            && manifestVerifiedAt != nil
    }

    public var hasVerifiedPackage: Bool {
        hasVerifiedManifest
            && packageIntegrityVerifiedAt != nil
            && installerTeamVerifiedAt != nil
    }

    public var isComplete: Bool {
        guard hasVerifiedPackage,
              installerOpenedAt != nil,
              let targetVersion,
              let targetBuild,
              observedInstalledVersion == targetVersion,
              observedInstalledBuild == targetBuild,
              postUpdateLaunchVerifiedAt != nil else {
            return false
        }
        return true
    }
}

private struct InAppUpdateEvidenceEnvelope:
    Codable,
    Sendable {
    let schemaVersion: Int
    let value: InAppUpdateEvidence
}

public struct InAppUpdateEvidenceStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    @discardableResult
    public func begin(
        currentVersion: String,
        currentBuild: Int,
        manifestURL: URL,
        expectedInstallerTeamID: String,
        now: Date = Date()
    ) throws -> InAppUpdateEvidence {
        let evidence = InAppUpdateEvidence(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            manifestURL: manifestURL,
            expectedInstallerTeamID:
                expectedInstallerTeamID,
            startedAt: now
        )
        try save(evidence)
        return evidence
    }

    @discardableResult
    public func recordManifestVerified(
        _ manifest: BlackstockUpdateManifest,
        now: Date = Date()
    ) throws -> InAppUpdateEvidence {
        var evidence = try requireEvidence()
        evidence.targetVersion = manifest.version
        evidence.targetBuild = manifest.build
        evidence.packageURL = manifest.packageURL
        evidence.packageSHA256 =
            manifest.sha256.lowercased()
        evidence.manifestVerifiedAt = now
        try save(evidence)
        return evidence
    }

    @discardableResult
    public func recordPackageVerified(
        _ manifest: BlackstockUpdateManifest,
        now: Date = Date()
    ) throws -> InAppUpdateEvidence {
        var evidence = try requireEvidence()
        try validate(
            evidence,
            matches: manifest
        )
        guard evidence.hasVerifiedManifest else {
            throw InAppUpdateEvidenceError
                .manifestMismatch
        }
        evidence.packageIntegrityVerifiedAt = now
        evidence.installerTeamVerifiedAt = now
        try save(evidence)
        return evidence
    }

    @discardableResult
    public func recordInstallerOpened(
        _ manifest: BlackstockUpdateManifest,
        now: Date = Date()
    ) throws -> InAppUpdateEvidence {
        var evidence = try requireEvidence()
        try validate(
            evidence,
            matches: manifest
        )
        guard evidence.hasVerifiedPackage else {
            throw InAppUpdateEvidenceError
                .packageNotVerified
        }
        evidence.installerOpenedAt = now
        try save(evidence)
        return evidence
    }

    @discardableResult
    public func recordPostUpdateLaunchIfMatching(
        installedVersion: String,
        installedBuild: Int,
        now: Date = Date()
    ) throws -> InAppUpdateEvidence? {
        guard var evidence = try load() else {
            return nil
        }
        guard evidence.installerOpenedAt != nil else {
            return evidence
        }
        guard evidence.targetVersion
                == installedVersion,
              evidence.targetBuild
                == installedBuild else {
            return evidence
        }

        evidence.observedInstalledVersion =
            installedVersion
        evidence.observedInstalledBuild =
            installedBuild
        evidence.postUpdateLaunchVerifiedAt = now
        try save(evidence)
        return evidence
    }

    public func load()
        throws -> InAppUpdateEvidence? {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization
            .jsonObject(with: data)
        guard let dictionary =
                object as? [String: Any],
              let rawVersion =
                dictionary["schemaVersion"],
              let version = rawVersion as? Int,
              version > 0 else {
            throw InAppUpdateEvidenceError
                .invalidSchemaVersion(0)
        }
        guard version
                <= InAppUpdateEvidenceSchema.current else {
            throw InAppUpdateEvidenceError
                .unsupportedFutureSchemaVersion(
                    version
                )
        }

        return try Self.decoder.decode(
            InAppUpdateEvidenceEnvelope.self,
            from: data
        ).value
    }

    private func requireEvidence()
        throws -> InAppUpdateEvidence {
        guard let evidence = try load() else {
            throw InAppUpdateEvidenceError
                .evidenceMissing
        }
        return evidence
    }

    private func validate(
        _ evidence: InAppUpdateEvidence,
        matches manifest: BlackstockUpdateManifest
    ) throws {
        guard evidence.targetVersion
                == manifest.version,
              evidence.targetBuild
                == manifest.build,
              evidence.packageURL
                == manifest.packageURL,
              evidence.packageSHA256
                == manifest.sha256.lowercased()
        else {
            throw InAppUpdateEvidenceError
                .manifestMismatch
        }
    }

    private func save(
        _ evidence: InAppUpdateEvidence
    ) throws {
        try FileManager.default.createDirectory(
            at: fileURL
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let envelope =
            InAppUpdateEvidenceEnvelope(
                schemaVersion:
                    InAppUpdateEvidenceSchema.current,
                value: evidence
            )
        let data = try Self.encoder.encode(
            envelope
        )
        try data.write(
            to: fileURL,
            options: [.atomic]
        )
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom {
            date,
            encoder in
            var container =
                encoder.singleValueContainer()
            try container.encode(
                date.timeIntervalSinceReferenceDate
            )
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom {
            decoder in
            let container =
                try decoder.singleValueContainer()
            let seconds =
                try container.decode(Double.self)
            return Date(
                timeIntervalSinceReferenceDate:
                    seconds
            )
        }
        return decoder
    }
}
