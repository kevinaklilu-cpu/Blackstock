import Foundation

public enum InAppUpdateEvidenceError:
    Error,
    Sendable,
    Equatable {
    case evidenceMissing
    case manifestMismatch
    case packageNotVerified
    case installerNotOpened
    case invalidCurrentAppProvenance
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

public enum InAppUpdateEvidenceSchema {
    public static let current = 6
}

public struct InAppUpdateEvidence:
    Codable,
    Sendable,
    Equatable {
    public let id: UUID
    public let currentVersion: String
    public let currentBuild: Int
    public let currentSourceCommitSHA: String
    public let currentExecutableSHA256: String
    public let currentAppPath: String
    public let currentApplicationTeamID: String
    public let currentDeveloperIDApplicationVerified: Bool
    public let currentInstallerReceiptPackageID: String
    public let currentInstallerReceiptVersion: String
    public let currentInstallerReceiptInstalledAt: Date
    public let currentInstallerReceiptVerified: Bool
    public let manifestURL: URL
    public let expectedInstallerTeamID: String
    public let startedAt: Date

    public var targetVersion: String?
    public var targetBuild: Int?
    public var targetSourceCommitSHA: String?
    public var packageURL: URL?
    public var packageSHA256: String?
    public var manifestVerifiedAt: Date?
    public var packageIntegrityVerifiedAt: Date?
    public var installerTeamVerifiedAt: Date?
    public var installerOpenedAt: Date?
    public var observedInstalledVersion: String?
    public var observedInstalledBuild: Int?
    public var observedInstalledSourceCommitSHA: String?
    public var observedInstalledExecutableSHA256: String?
    public var observedInstalledAppPath: String?
    public var observedApplicationTeamID: String?
    public var observedDeveloperIDApplicationVerified: Bool?
    public var observedInstallerReceiptPackageID: String?
    public var observedInstallerReceiptVersion: String?
    public var observedInstallerReceiptInstalledAt: Date?
    public var observedInstallerReceiptVerified: Bool?
    public var postUpdateLaunchVerifiedAt: Date?

    public init(
        id: UUID = UUID(),
        currentVersion: String,
        currentBuild: Int,
        currentSourceCommitSHA: String,
        currentExecutableSHA256: String,
        currentAppPath: String,
        currentApplicationTeamID: String,
        currentDeveloperIDApplicationVerified: Bool,
        currentInstallerReceiptPackageID: String,
        currentInstallerReceiptVersion: String,
        currentInstallerReceiptInstalledAt: Date,
        currentInstallerReceiptVerified: Bool,
        manifestURL: URL,
        expectedInstallerTeamID: String,
        startedAt: Date
    ) {
        self.id = id
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.currentSourceCommitSHA =
            currentSourceCommitSHA.lowercased()
        self.currentExecutableSHA256 =
            currentExecutableSHA256.lowercased()
        self.currentAppPath = currentAppPath
        self.currentApplicationTeamID =
            currentApplicationTeamID
        self.currentDeveloperIDApplicationVerified =
            currentDeveloperIDApplicationVerified
        self.currentInstallerReceiptPackageID =
            currentInstallerReceiptPackageID
        self.currentInstallerReceiptVersion =
            currentInstallerReceiptVersion
        self.currentInstallerReceiptInstalledAt =
            currentInstallerReceiptInstalledAt
        self.currentInstallerReceiptVerified =
            currentInstallerReceiptVerified
        self.manifestURL = manifestURL
        self.expectedInstallerTeamID =
            expectedInstallerTeamID
        self.startedAt = startedAt
        targetVersion = nil
        targetBuild = nil
        targetSourceCommitSHA = nil
        packageURL = nil
        packageSHA256 = nil
        manifestVerifiedAt = nil
        packageIntegrityVerifiedAt = nil
        installerTeamVerifiedAt = nil
        installerOpenedAt = nil
        observedInstalledVersion = nil
        observedInstalledBuild = nil
        observedInstalledSourceCommitSHA = nil
        observedInstalledExecutableSHA256 = nil
        observedInstalledAppPath = nil
        observedApplicationTeamID = nil
        observedDeveloperIDApplicationVerified = nil
        observedInstallerReceiptPackageID = nil
        observedInstallerReceiptVersion = nil
        observedInstallerReceiptInstalledAt = nil
        observedInstallerReceiptVerified = nil
        postUpdateLaunchVerifiedAt = nil
    }

    public var hasVerifiedManifest: Bool {
        targetVersion != nil
            && targetBuild != nil
            && targetSourceCommitSHA != nil
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
        guard currentBuild > 0,
              !currentVersion.isEmpty,
              currentSourceCommitSHA.count == 40,
              currentSourceCommitSHA
                .allSatisfy({ $0.isHexDigit }),
              currentExecutableSHA256.count == 64,
              currentExecutableSHA256
                .allSatisfy({ $0.isHexDigit }),
              currentAppPath
                == "/Applications/Blackstock.app",
              currentApplicationTeamID
                == expectedInstallerTeamID,
              currentDeveloperIDApplicationVerified,
              currentInstallerReceiptPackageID
                == "de.blackstock.app",
              currentInstallerReceiptVersion
                == currentVersion,
              currentInstallerReceiptInstalledAt
                <= startedAt.addingTimeInterval(1),
              currentInstallerReceiptVerified,
              hasVerifiedPackage,
              installerOpenedAt != nil,
              let targetVersion,
              let targetBuild,
              let targetSourceCommitSHA,
              observedInstalledVersion == targetVersion,
              observedInstalledBuild == targetBuild,
              observedInstalledSourceCommitSHA
                == targetSourceCommitSHA,
              let observedInstalledExecutableSHA256,
              observedInstalledExecutableSHA256.count == 64,
              observedInstalledExecutableSHA256
                .allSatisfy({ $0.isHexDigit }),
              observedInstalledAppPath
                == "/Applications/Blackstock.app",
              observedApplicationTeamID
                == expectedInstallerTeamID,
              observedDeveloperIDApplicationVerified
                == true,
              observedInstallerReceiptPackageID
                == "de.blackstock.app",
              observedInstallerReceiptVersion
                == targetVersion,
              let observedInstallerReceiptInstalledAt,
              let installerOpenedAt,
              observedInstallerReceiptInstalledAt
                > currentInstallerReceiptInstalledAt,
              observedInstallerReceiptInstalledAt
                >= installerOpenedAt.addingTimeInterval(-1),
              observedInstallerReceiptVerified
                == true,
              let postUpdateLaunchVerifiedAt,
              observedInstallerReceiptInstalledAt
                <= postUpdateLaunchVerifiedAt.addingTimeInterval(1) else {
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
        currentSourceCommitSHA: String = "",
        currentExecutableSHA256: String = "",
        currentAppPath: String = "",
        currentApplicationTeamID: String = "",
        currentDeveloperIDApplicationVerified: Bool = false,
        currentInstallerReceiptPackageID: String = "",
        currentInstallerReceiptVersion: String = "",
        currentInstallerReceiptInstalledAt: Date? = nil,
        currentInstallerReceiptVerified: Bool = false,
        manifestURL: URL,
        expectedInstallerTeamID: String,
        now: Date = Date()
    ) throws -> InAppUpdateEvidence {
        guard currentBuild > 0,
              !currentVersion.isEmpty,
              currentSourceCommitSHA.count == 40,
              currentSourceCommitSHA.allSatisfy({ $0.isHexDigit }),
              currentExecutableSHA256.count == 64,
              currentExecutableSHA256.allSatisfy({ $0.isHexDigit }),
              currentAppPath == "/Applications/Blackstock.app",
              !currentApplicationTeamID.isEmpty,
              currentApplicationTeamID == expectedInstallerTeamID,
              currentDeveloperIDApplicationVerified,
              currentInstallerReceiptPackageID == "de.blackstock.app",
              currentInstallerReceiptVersion == currentVersion,
              let currentInstallerReceiptInstalledAt,
              currentInstallerReceiptInstalledAt
                <= now.addingTimeInterval(1),
              currentInstallerReceiptVerified else {
            throw InAppUpdateEvidenceError
                .invalidCurrentAppProvenance
        }

        let evidence = InAppUpdateEvidence(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            currentSourceCommitSHA:
                currentSourceCommitSHA,
            currentExecutableSHA256:
                currentExecutableSHA256,
            currentAppPath:
                currentAppPath,
            currentApplicationTeamID:
                currentApplicationTeamID,
            currentDeveloperIDApplicationVerified:
                currentDeveloperIDApplicationVerified,
            currentInstallerReceiptPackageID:
                currentInstallerReceiptPackageID,
            currentInstallerReceiptVersion:
                currentInstallerReceiptVersion,
            currentInstallerReceiptInstalledAt:
                currentInstallerReceiptInstalledAt,
            currentInstallerReceiptVerified:
                currentInstallerReceiptVerified,
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
        evidence.targetSourceCommitSHA =
            manifest.sourceCommitSHA.lowercased()
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
        installedSourceCommitSHA: String,
        installedExecutableSHA256: String,
        installedAppPath: String,
        applicationTeamID: String,
        developerIDApplicationVerified: Bool,
        installerReceiptPackageID: String,
        installerReceiptVersion: String,
        installerReceiptInstalledAt: Date,
        installerReceiptVerified: Bool,
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
                == installedBuild,
              evidence.targetSourceCommitSHA
                == installedSourceCommitSHA.lowercased(),
              installedExecutableSHA256.count == 64,
              installedExecutableSHA256
                .allSatisfy({ $0.isHexDigit }),
              installedAppPath
                == "/Applications/Blackstock.app",
              applicationTeamID
                == evidence.expectedInstallerTeamID,
              developerIDApplicationVerified,
              installerReceiptPackageID
                == "de.blackstock.app",
              installerReceiptVersion
                == installedVersion,
              installerReceiptInstalledAt
                > evidence.currentInstallerReceiptInstalledAt,
              let installerOpenedAt =
                evidence.installerOpenedAt,
              installerReceiptInstalledAt
                >= installerOpenedAt.addingTimeInterval(-1),
              installerReceiptInstalledAt
                <= now.addingTimeInterval(1),
              installerReceiptVerified
        else {
            return evidence
        }

        evidence.observedInstalledVersion =
            installedVersion
        evidence.observedInstalledBuild =
            installedBuild
        evidence.observedInstalledSourceCommitSHA =
            installedSourceCommitSHA.lowercased()
        evidence.observedInstalledExecutableSHA256 =
            installedExecutableSHA256.lowercased()
        evidence.observedInstalledAppPath =
            installedAppPath
        evidence.observedApplicationTeamID =
            applicationTeamID
        evidence.observedDeveloperIDApplicationVerified =
            developerIDApplicationVerified
        evidence.observedInstallerReceiptPackageID =
            installerReceiptPackageID
        evidence.observedInstallerReceiptVersion =
            installerReceiptVersion
        evidence.observedInstallerReceiptInstalledAt =
            installerReceiptInstalledAt
        evidence.observedInstallerReceiptVerified =
            installerReceiptVerified
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
              evidence.targetSourceCommitSHA
                == manifest.sourceCommitSHA.lowercased(),
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
