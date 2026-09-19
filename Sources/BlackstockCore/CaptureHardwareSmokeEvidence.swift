import Foundation

public struct CaptureHardwarePathEvidence:
    Codable,
    Sendable,
    Equatable {
    public var permissionGranted: Bool
    public var recordingCreated: Bool
    public var durationSeconds: Double
    public var persistedToProject: Bool
    public var decodedSamples: Int64?
    public var videoTrackPresent: Bool?
    public var projectID: UUID?
    public var recordedLaunchID: UUID?
    public var persistedFilePath: String?
    public var persistedFileSHA256: String?

    public init(
        permissionGranted: Bool = false,
        recordingCreated: Bool = false,
        durationSeconds: Double = 0,
        persistedToProject: Bool = false,
        decodedSamples: Int64? = nil,
        videoTrackPresent: Bool? = nil,
        projectID: UUID? = nil,
        recordedLaunchID: UUID? = nil,
        persistedFilePath: String? = nil,
        persistedFileSHA256: String? = nil
    ) {
        self.permissionGranted = permissionGranted
        self.recordingCreated = recordingCreated
        self.durationSeconds = durationSeconds
        self.persistedToProject = persistedToProject
        self.decodedSamples = decodedSamples
        self.videoTrackPresent = videoTrackPresent
        self.projectID = projectID
        self.recordedLaunchID = recordedLaunchID
        self.persistedFilePath = persistedFilePath
        self.persistedFileSHA256 =
            persistedFileSHA256?.lowercased()
    }

    public func satisfies(
        kind: CaptureKind,
        minimumDurationSeconds: Double = 5
    ) -> Bool {
        guard permissionGranted,
              recordingCreated,
              persistedToProject,
              durationSeconds >= minimumDurationSeconds else {
            return false
        }

        switch kind {
        case .camera, .screen:
            return videoTrackPresent == true
        case .microphone, .systemAudio:
            return (decodedSamples ?? 0) > 0
        }
    }
}

public struct CaptureHardwareSmokeEvidence:
    Codable,
    Sendable,
    Equatable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var testedAt: Date
    public var blackstockVersion: String
    public var blackstockBuild: String
    public var blackstockSourceCommitSHA: String
    public var macOSVersion: String
    public var hardwareModel: String
    public var installedFromPackage: Bool
    public var applicationTeamID: String
    public var developerIDApplicationVerified: Bool

    public var camera: CaptureHardwarePathEvidence
    public var microphone: CaptureHardwarePathEvidence
    public var screen: CaptureHardwarePathEvidence
    public var systemAudio: CaptureHardwarePathEvidence

    public var deniedPermissionHardStopPassed: Bool
    public var temporaryCleanupPassed: Bool
    public var appRestartPersistencePassed: Bool
    public var restartVerifiedLaunchID: UUID?

    public var deniedPermissionKinds: Set<CaptureKind>
    public var temporaryCleanupKinds: Set<CaptureKind>

    public init(
        testedAt: Date,
        blackstockVersion: String,
        blackstockBuild: String,
        blackstockSourceCommitSHA: String,
        macOSVersion: String,
        hardwareModel: String,
        installedFromPackage: Bool,
        applicationTeamID: String,
        developerIDApplicationVerified: Bool
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.testedAt = testedAt
        self.blackstockVersion = blackstockVersion
        self.blackstockBuild = blackstockBuild
        self.blackstockSourceCommitSHA =
            blackstockSourceCommitSHA.lowercased()
        self.macOSVersion = macOSVersion
        self.hardwareModel = hardwareModel
        self.installedFromPackage = installedFromPackage
        self.applicationTeamID = applicationTeamID
        self.developerIDApplicationVerified =
            developerIDApplicationVerified
        camera = .init()
        microphone = .init()
        screen = .init()
        systemAudio = .init()
        deniedPermissionHardStopPassed = false
        temporaryCleanupPassed = false
        appRestartPersistencePassed = false
        restartVerifiedLaunchID = nil
        deniedPermissionKinds = []
        temporaryCleanupKinds = []
    }

    public subscript(
        kind: CaptureKind
    ) -> CaptureHardwarePathEvidence {
        get {
            switch kind {
            case .camera: return camera
            case .microphone: return microphone
            case .screen: return screen
            case .systemAudio: return systemAudio
            }
        }
        set {
            switch kind {
            case .camera: camera = newValue
            case .microphone: microphone = newValue
            case .screen: screen = newValue
            case .systemAudio: systemAudio = newValue
            }
        }
    }

    public mutating func recordDeniedHardStop(
        for kinds: Set<CaptureKind>
    ) {
        deniedPermissionKinds.formUnion(kinds)
        deniedPermissionHardStopPassed =
            Set(CaptureKind.allCases)
                .isSubset(of: deniedPermissionKinds)
    }

    public mutating func recordTemporaryCleanup(
        for kinds: Set<CaptureKind>
    ) {
        temporaryCleanupKinds.formUnion(kinds)
        temporaryCleanupPassed =
            Set(CaptureKind.allCases)
                .isSubset(of: temporaryCleanupKinds)
    }

    public mutating func reconcileRestartPersistence(
        currentLaunchID: UUID
    ) {
        let paths = CaptureKind.allCases.map {
            self[$0]
        }
        guard paths.allSatisfy({
            $0.persistedToProject
                && $0.projectID != nil
                && $0.recordedLaunchID != nil
                && $0.persistedFilePath != nil
                && $0.persistedFileSHA256 != nil
        }) else {
            appRestartPersistencePassed = false
            restartVerifiedLaunchID = nil
            return
        }

        appRestartPersistencePassed =
            paths.allSatisfy {
                guard $0.recordedLaunchID
                        != currentLaunchID,
                      let path =
                        $0.persistedFilePath else {
                    return false
                }
                return FileManager.default.fileExists(
                    atPath: path
                )
            }
        restartVerifiedLaunchID =
            appRestartPersistencePassed
                ? currentLaunchID
                : nil
    }

    public var allCanonicalPathsPass: Bool {
        CaptureKind.allCases.allSatisfy {
            self[$0].satisfies(kind: $0)
        }
    }

    public var isComplete: Bool {
        installedFromPackage
            && developerIDApplicationVerified
            && !applicationTeamID.isEmpty
            && allCanonicalPathsPass
            && deniedPermissionHardStopPassed
            && temporaryCleanupPassed
            && appRestartPersistencePassed
            && !blackstockVersion.isEmpty
            && !blackstockBuild.isEmpty
            && blackstockSourceCommitSHA.count == 40
            && blackstockSourceCommitSHA
                .allSatisfy({ $0.isHexDigit })
            && !macOSVersion.isEmpty
            && !hardwareModel.isEmpty
    }
}

public enum CaptureHardwareSmokeEvidenceStoreError:
    Error,
    Sendable,
    Equatable {
    case invalidSchemaVersion(Int)
    case unsupportedFutureSchemaVersion(Int)
}

public struct CaptureHardwareSmokeEvidenceStore:
    Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load()
        throws -> CaptureHardwareSmokeEvidence? {
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
            throw CaptureHardwareSmokeEvidenceStoreError
                .invalidSchemaVersion(0)
        }
        guard version
                <= CaptureHardwareSmokeEvidence
                    .currentSchemaVersion else {
            throw CaptureHardwareSmokeEvidenceStoreError
                .unsupportedFutureSchemaVersion(
                    version
                )
        }
        guard version
                == CaptureHardwareSmokeEvidence
                    .currentSchemaVersion else {
            // Legacy evidence lacks the complete production-app
            // provenance contract and must be re-recorded.
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            CaptureHardwareSmokeEvidence.self,
            from: data
        )
    }

    public func save(
        _ evidence: CaptureHardwareSmokeEvidence
    ) throws {
        try FileManager.default.createDirectory(
            at: fileURL
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        let data = try encoder.encode(evidence)
        try data.write(
            to: fileURL,
            options: [.atomic]
        )
    }
}
