#if os(macOS)
import AVFoundation
import BlackstockCore
import CryptoKit
import Foundation

enum BlackstockCaptureHardwareAudit {
    static let launchID = UUID()

    static func recordDeniedPermission(
        for kind: CaptureKind
    ) {
        updateEvidence { evidence in
            evidence.recordDeniedHardStop(
                for: canonicalKinds(for: kind)
            )
        }
    }

    static func recordPersistedCapture(
        kind: CaptureKind,
        fileURL: URL,
        projectID: UUID
    ) async {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ),
        isExpectedPersistedProjectCapture(
            fileURL: fileURL,
            projectID: projectID,
            kind: kind
        ) else {
            return
        }

        let asset = AVURLAsset(url: fileURL)
        let duration: Double
        do {
            let value = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(value)
            duration = seconds.isFinite
                ? max(seconds, 0)
                : 0
        } catch {
            duration = 0
        }

        let hasVideoTrack: Bool
        do {
            hasVideoTrack = try await asset
                .loadTracks(withMediaType: .video)
                .isEmpty == false
        } catch {
            hasVideoTrack = false
        }

        let decodedSamples: Int64
        do {
            let assessment =
                try await LocalAudioSignalAnalyzer()
                    .analyze(url: fileURL)
            decodedSamples =
                assessment.snapshot
                    .analyzedSampleCount
        } catch {
            decodedSamples = 0
        }

        let snapshot =
            CaptureCapabilityProbe().inspect()
        let persistedSHA256 =
            sha256(of: fileURL)

        updateEvidence { evidence in
            let kinds = canonicalKinds(
                for: kind
            )
            evidence.temporaryCleanupKinds
                .subtract(kinds)
            evidence.temporaryCleanupPassed =
                Set(CaptureKind.allCases)
                    .isSubset(
                        of: evidence
                            .temporaryCleanupKinds
                    )
            evidence.appRestartPersistencePassed =
                false
            evidence.restartVerifiedLaunchID =
                nil

            for canonicalKind in kinds {
                let permissionGranted =
                    snapshot.capability(
                        for: canonicalKind
                    )?.authorization
                        == .authorized

                evidence[canonicalKind] =
                    CaptureHardwarePathEvidence(
                        permissionGranted:
                            permissionGranted,
                        recordingCreated: true,
                        durationSeconds: duration,
                        persistedToProject: true,
                        decodedSamples:
                            canonicalKind
                                == .microphone
                            || canonicalKind
                                == .systemAudio
                                ? decodedSamples
                                : nil,
                        videoTrackPresent:
                            canonicalKind
                                == .camera
                            || canonicalKind
                                == .screen
                                ? hasVideoTrack
                                : nil,
                        projectID: projectID,
                        recordedLaunchID:
                            launchID,
                        persistedFilePath:
                            fileURL.path,
                        persistedFileSHA256:
                            persistedSHA256
                    )
            }

            evidence.testedAt = Date()
        }
    }

    static func recordTemporaryCleanup(
        for kind: CaptureKind,
        temporaryURL: URL
    ) {
        guard !FileManager.default
            .fileExists(
                atPath: temporaryURL.path
            ) else {
            return
        }

        updateEvidence { evidence in
            evidence.recordTemporaryCleanup(
                for: canonicalKinds(for: kind)
            )
        }
    }

    static func reconcilePostRestart() {
        updateEvidence { evidence in
            evidence.reconcileRestartPersistence(
                currentLaunchID: launchID
            )
            evidence.testedAt = Date()
        }
    }

    static func loadEvidence()
        -> CaptureHardwareSmokeEvidence? {
        try? makeStore().load()
    }

    static func evidenceURL() -> URL? {
        try? makeStore().fileURL
    }

    private static func updateEvidence(
        _ update:
            (inout CaptureHardwareSmokeEvidence)
                -> Void
    ) {
        do {
            let store = try makeStore()
            var evidence =
                try currentEvidence(store: store)
            update(&evidence)
            try store.save(evidence)
        } catch {
            // Capture darf wegen Diagnose-Evidenz
            // niemals fehlschlagen. Ein fehlender
            // Nachweis hält das Release-Gate offen.
        }
    }

    private static func currentEvidence(
        store: CaptureHardwareSmokeEvidenceStore
    ) throws -> CaptureHardwareSmokeEvidence {
        let metadata = currentMetadata()
        let osVersion = ProcessInfo.processInfo
            .operatingSystemVersionString
        let model = hardwareModel()
        let receipt = installerReceiptMetadata(
            expectedVersion: metadata.version
        )
        let installed = installedFromPackage(
            receiptVerified: receipt.verified
        )
        let executableSHA256 =
            Bundle.main.executableURL
                .flatMap { sha256(of: $0) } ?? ""
        let signing = applicationSigningMetadata(
            expectedTeamID: metadata.expectedTeamID
        )

        if let existing = try store.load(),
           existing.blackstockVersion
                == metadata.version,
           existing.blackstockBuild
                == metadata.build,
           existing.blackstockSourceCommitSHA
                == metadata.sourceCommitSHA,
           existing.macOSVersion == osVersion,
           existing.hardwareModel == model,
           existing.installedFromPackage
                == installed,
           existing.installerReceiptPackageID
                == receipt.packageID,
           existing.installerReceiptVersion
                == receipt.version,
           existing.installerReceiptInstalledAt
                == receipt.installedAt,
           existing.installerReceiptVerified
                == receipt.verified,
           existing.applicationTeamID
                == signing.teamID,
           existing.developerIDApplicationVerified
                == signing.verified,
           existing.applicationExecutableSHA256
                == executableSHA256 {
            return existing
        }

        return CaptureHardwareSmokeEvidence(
            testedAt: Date(),
            blackstockVersion:
                metadata.version,
            blackstockBuild:
                metadata.build,
            blackstockSourceCommitSHA:
                metadata.sourceCommitSHA,
            macOSVersion: osVersion,
            hardwareModel: model,
            installedFromPackage: installed,
            installerReceiptPackageID:
                receipt.packageID,
            installerReceiptVersion:
                receipt.version,
            installerReceiptInstalledAt:
                receipt.installedAt,
            installerReceiptVerified:
                receipt.verified,
            applicationTeamID: signing.teamID,
            developerIDApplicationVerified:
                signing.verified,
            applicationExecutableSHA256:
                executableSHA256
        )
    }

    private static func isExpectedPersistedProjectCapture(
        fileURL: URL,
        projectID: UUID,
        kind: CaptureKind
    ) -> Bool {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let projectDirectory = base
                .appendingPathComponent(
                    "Blackstock",
                    isDirectory: true
                )
                .appendingPathComponent(
                    "Projects",
                    isDirectory: true
                )
                .appendingPathComponent(
                    projectID.uuidString,
                    isDirectory: true
                )
            let expectedDirectory = projectDirectory
                .appendingPathComponent(
                    kind == .microphone
                        ? "Captures"
                        : "Media",
                    isDirectory: true
                )
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let resolvedFileURL = fileURL
                .resolvingSymlinksInPath()
                .standardizedFileURL

            guard resolvedFileURL
                    .deletingLastPathComponent()
                    .path
                    == expectedDirectory.path,
                  UUID(
                    uuidString: resolvedFileURL
                        .deletingPathExtension()
                        .lastPathComponent
                  ) != nil else {
                return false
            }

            return FileManager.default
                .isReadableFile(
                    atPath: resolvedFileURL.path
                )
        } catch {
            return false
        }
    }

    private static func makeStore()
        throws -> CaptureHardwareSmokeEvidenceStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent(
                "Blackstock",
                isDirectory: true
            )
            .appendingPathComponent(
                "Diagnostics",
                isDirectory: true
            )
        return CaptureHardwareSmokeEvidenceStore(
            fileURL: directory
                .appendingPathComponent(
                    "capture-hardware-smoke.json"
                )
        )
    }

    private static func sha256(
        of url: URL
    ) -> String? {
        guard let handle =
                try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        do {
            while true {
                let data = try handle.read(
                    upToCount: 1_048_576
                ) ?? Data()
                if data.isEmpty {
                    break
                }
                hasher.update(data: data)
            }
        } catch {
            return nil
        }

        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func currentMetadata()
        -> (
            version: String,
            build: String,
            sourceCommitSHA: String,
            expectedTeamID: String
        ) {
        let version = (
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleShortVersionString"
            ) as? String ?? "UNBEKANNT"
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let build = (
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleVersion"
            ) as? String ?? "UNBEKANNT"
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let sourceCommitSHA = (
            Bundle.main.object(
                forInfoDictionaryKey:
                    "BlackstockSourceCommitSHA"
            ) as? String ?? "UNBEKANNT"
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let expectedTeamID = (
            Bundle.main.object(
                forInfoDictionaryKey:
                    "BlackstockUpdateInstallerTeamID"
            ) as? String ?? ""
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return (
            version.isEmpty ? "UNBEKANNT" : version,
            build.isEmpty ? "UNBEKANNT" : build,
            sourceCommitSHA.count == 40
                && sourceCommitSHA
                    .allSatisfy({ $0.isHexDigit })
                ? sourceCommitSHA.lowercased()
                : "UNBEKANNT",
            expectedTeamID
        )
    }

    private static func applicationSigningMetadata(
        expectedTeamID: String
    ) -> (teamID: String, verified: Bool) {
        guard !expectedTeamID.isEmpty else {
            return ("", false)
        }

        let verifyProcess = Process()
        verifyProcess.executableURL = URL(
            fileURLWithPath: "/usr/bin/codesign"
        )
        verifyProcess.arguments = [
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            Bundle.main.bundleURL.path
        ]
        let verifyPipe = Pipe()
        verifyProcess.standardOutput = verifyPipe
        verifyProcess.standardError = verifyPipe

        do {
            try verifyProcess.run()
            verifyProcess.waitUntilExit()
            guard verifyProcess.terminationStatus == 0 else {
                return ("", false)
            }
        } catch {
            return ("", false)
        }

        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/codesign"
        )
        process.arguments = [
            "--display",
            "--verbose=4",
            Bundle.main.bundleURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return ("", false)
            }
            let output = String(
                decoding: pipe.fileHandleForReading
                    .readDataToEndOfFile(),
                as: UTF8.self
            )
            let prefix = "TeamIdentifier="
            guard let line = output
                    .split(whereSeparator: { $0.isNewline })
                    .map(String.init)
                    .first(where: {
                        $0.hasPrefix(prefix)
                    }) else {
                return ("", false)
            }
            let teamID = String(
                line.dropFirst(prefix.count)
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let verified =
                output.contains(
                    "Authority=Developer ID Application"
                )
                && teamID == expectedTeamID
            return (teamID, verified)
        } catch {
            return ("", false)
        }
    }

    private static func installerReceiptMetadata(
        expectedVersion: String
    ) -> (
        packageID: String,
        version: String,
        installedAt: Date,
        verified: Bool
    ) {
        let expectedPackageID = "de.blackstock.app"
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/sbin/pkgutil"
        )
        process.arguments = [
            "--pkg-info-plist",
            expectedPackageID
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return ("", "", .distantPast, false)
            }
            let data = pipe.fileHandleForReading
                .readDataToEndOfFile()
            guard let plist =
                    try PropertyListSerialization
                        .propertyList(
                            from: data,
                            options: [],
                            format: nil
                        ) as? [String: Any],
                  let packageID =
                    plist["pkgid"] as? String,
                  let version =
                    plist["pkg-version"] as? String else {
                return ("", "", .distantPast, false)
            }

            let volume =
                plist["volume"] as? String
            let installLocation =
                plist["install-location"] as? String
            let installedAtSeconds: TimeInterval?
            if let number =
                    plist["install-time"] as? NSNumber {
                installedAtSeconds =
                    number.doubleValue
            } else if let string =
                        plist["install-time"] as? String,
                      let parsed = TimeInterval(string) {
                installedAtSeconds = parsed
            } else {
                installedAtSeconds = nil
            }
            let installedAt: Date
            if let seconds = installedAtSeconds,
               seconds.isFinite,
               seconds > 0 {
                installedAt = Date(
                    timeIntervalSince1970: seconds
                )
            } else {
                installedAt = Date.distantPast
            }
            let verified =
                packageID == expectedPackageID
                && version == expectedVersion
                && volume == "/"
                && installLocation == "/"
                && installedAt != Date.distantPast
            return (
                packageID,
                version,
                installedAt,
                verified
            )
        } catch {
            return ("", "", .distantPast, false)
        }
    }

    private static func installedFromPackage(
        receiptVerified: Bool
    ) -> Bool {
        receiptVerified
            && Bundle.main.bundleURL
                .standardizedFileURL.path
                == "/Applications/Blackstock.app"
    }

    private static func hardwareModel() -> String {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/sbin/sysctl"
        )
        process.arguments = ["-n", "hw.model"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "UNBEKANNT"
            }
            let data = pipe.fileHandleForReading
                .readDataToEndOfFile()
            let model = String(
                decoding: data,
                as: UTF8.self
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return model.isEmpty
                ? "UNBEKANNT"
                : model
        } catch {
            return "UNBEKANNT"
        }
    }

    private static func canonicalKinds(
        for kind: CaptureKind
    ) -> Set<CaptureKind> {
        switch kind {
        case .screen, .systemAudio:
            return [.screen, .systemAudio]
        case .camera:
            return [.camera]
        case .microphone:
            return [.microphone]
        }
    }
}
#endif
