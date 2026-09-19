import XCTest
@testable import BlackstockCore

final class CaptureHardwareSmokeEvidenceTests:
    XCTestCase {

    func testCompleteEvidenceRequiresAllFourPathsAndExternalChecks()
        throws {
        var evidence = makeEvidence()
        let projectID = UUID()
        let previousLaunch = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let cameraFile = try persistedFile(root, "camera.mov")
        let microphoneFile = try persistedFile(root, "microphone.m4a")
        let screenFile = try persistedFile(root, "screen.mp4")

        evidence.camera = .init(
            permissionGranted: true,
            recordingCreated: true,
            durationSeconds: 5.2,
            persistedToProject: true,
            videoTrackPresent: true,
            projectID: projectID,
            recordedLaunchID: previousLaunch,
            persistedFilePath: cameraFile.path
        )
        evidence.microphone = .init(
            permissionGranted: true,
            recordingCreated: true,
            durationSeconds: 5.1,
            persistedToProject: true,
            decodedSamples: 24_000,
            projectID: projectID,
            recordedLaunchID: previousLaunch,
            persistedFilePath: microphoneFile.path
        )
        evidence.screen = .init(
            permissionGranted: true,
            recordingCreated: true,
            durationSeconds: 5.3,
            persistedToProject: true,
            videoTrackPresent: true,
            projectID: projectID,
            recordedLaunchID: previousLaunch,
            persistedFilePath: screenFile.path
        )
        evidence.systemAudio = .init(
            permissionGranted: true,
            recordingCreated: true,
            durationSeconds: 5.3,
            persistedToProject: true,
            decodedSamples: 48_000,
            projectID: projectID,
            recordedLaunchID: previousLaunch,
            persistedFilePath: screenFile.path
        )

        evidence.recordDeniedHardStop(
            for: Set(CaptureKind.allCases)
        )
        evidence.recordTemporaryCleanup(
            for: Set(CaptureKind.allCases)
        )
        evidence.reconcileRestartPersistence(
            currentLaunchID: UUID()
        )

        XCTAssertTrue(evidence.allCanonicalPathsPass)
        XCTAssertTrue(evidence.isComplete)
    }

    func testRestartPersistenceRequiresDifferentProcessLaunch()
        throws {
        var evidence = makeEvidence()
        let launchID = UUID()
        let projectID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        for kind in CaptureKind.allCases {
            let file = try persistedFile(
                root,
                "\(kind.rawValue).dat"
            )
            evidence[kind] = .init(
                permissionGranted: true,
                recordingCreated: true,
                durationSeconds: 6,
                persistedToProject: true,
                decodedSamples:
                    kind == .microphone
                    || kind == .systemAudio
                        ? 1
                        : nil,
                videoTrackPresent:
                    kind == .camera
                    || kind == .screen
                        ? true
                        : nil,
                projectID: projectID,
                recordedLaunchID: launchID,
                persistedFilePath: file.path
            )
        }

        evidence.reconcileRestartPersistence(
            currentLaunchID: launchID
        )
        XCTAssertFalse(
            evidence.appRestartPersistencePassed
        )

        evidence.reconcileRestartPersistence(
            currentLaunchID: UUID()
        )
        XCTAssertTrue(
            evidence.appRestartPersistencePassed
        )
    }

    func testStoreRoundTripsValidatorCompatibleShape()
        throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(
                at: root
            )
        }

        let store =
            CaptureHardwareSmokeEvidenceStore(
                fileURL: root
                    .appendingPathComponent(
                        "capture-hardware-smoke.json"
                    )
            )
        let evidence = makeEvidence()
        try store.save(evidence)

        XCTAssertEqual(
            try store.load(),
            evidence
        )

        let data = try Data(
            contentsOf: store.fileURL
        )
        let object = try XCTUnwrap(
            JSONSerialization
                .jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(
            object["schemaVersion"] as? Int,
            1
        )
        XCTAssertNotNil(object["camera"])
        XCTAssertNotNil(object["systemAudio"])
    }

    private func persistedFile(
        _ root: URL,
        _ name: String
    ) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data([0x01]).write(to: url)
        return url
    }

    private func makeEvidence()
        -> CaptureHardwareSmokeEvidence {
        CaptureHardwareSmokeEvidence(
            testedAt: Date(
                timeIntervalSince1970:
                    1_789_000_000
            ),
            blackstockVersion: "1.0.0",
            blackstockBuild: "100",
            macOSVersion: "26.6.2",
            hardwareModel: "MacBookProTest",
            installedFromPackage: true
        )
    }
}
