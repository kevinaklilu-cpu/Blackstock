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
        let model = hardwareModel()
        let installed = installedFromPackage()

        if let existing = try store.load(),
           existing.blackstockVersion
                == metadata.version,
           existing.blackstockBuild
                == metadata.build,
           existing.blackstockSourceCommitSHA
                == metadata.sourceCommitSHA,
           existing.hardwareModel == model,
           existing.installedFromPackage
                == installed {
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
            macOSVersion:
                ProcessInfo.processInfo
                    .operatingSystemVersionString,
            hardwareModel: model,
            installedFromPackage: installed
        )
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
            sourceCommitSHA: String
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
        return (
            version.isEmpty ? "UNBEKANNT" : version,
            build.isEmpty ? "UNBEKANNT" : build,
            sourceCommitSHA.count == 40
                && sourceCommitSHA
                    .allSatisfy({ $0.isHexDigit })
                ? sourceCommitSHA.lowercased()
                : "UNBEKANNT"
        )
    }

    private static func installedFromPackage()
        -> Bool {
        Bundle.main.bundleURL
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
