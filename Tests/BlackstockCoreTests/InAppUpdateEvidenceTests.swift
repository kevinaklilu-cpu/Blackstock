import XCTest
@testable import BlackstockCore

final class InAppUpdateEvidenceTests:
    XCTestCase {

    func testVerifiedUpdateCompletesOnlyAfterTargetBuildLaunch()
        throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }

        let store = InAppUpdateEvidenceStore(
            fileURL: root
                .appendingPathComponent(
                    "update-evidence.json"
                )
        )
        let manifest = makeManifest(
            version: "1.0.0",
            build: 100
        )

        _ = try store.begin(
            currentVersion: "0.9.0",
            currentBuild: 90,
            manifestURL: URL(
                string:
                    "https://updates.blackstock.app/update-manifest.json"
            )!,
            expectedInstallerTeamID:
                "ABC123TEAM",
            now: Date(
                timeIntervalSinceReferenceDate:
                    100.125
            )
        )
        _ = try store.recordManifestVerified(
            manifest,
            now: Date(
                timeIntervalSinceReferenceDate:
                    101.25
            )
        )
        _ = try store.recordPackageVerified(
            manifest,
            now: Date(
                timeIntervalSinceReferenceDate:
                    102.5
            )
        )
        _ = try store.recordInstallerOpened(
            manifest,
            now: Date(
                timeIntervalSinceReferenceDate:
                    103.75
            )
        )

        let oldLaunch =
            try store
                .recordPostUpdateLaunchIfMatching(
                    installedVersion: "0.9.0",
                    installedBuild: 90,
                    now: Date(
                        timeIntervalSinceReferenceDate:
                            104
                    )
                )
        XCTAssertEqual(
            oldLaunch?.isComplete,
            false
        )

        let completed =
            try store
                .recordPostUpdateLaunchIfMatching(
                    installedVersion: "1.0.0",
                    installedBuild: 100,
                    now: Date(
                        timeIntervalSinceReferenceDate:
                            105.875
                    )
                )
        XCTAssertEqual(
            completed?.isComplete,
            true
        )

        let reloaded = try store.load()
        XCTAssertEqual(reloaded, completed)
        XCTAssertEqual(
            reloaded?.observedInstalledVersion,
            "1.0.0"
        )
        XCTAssertEqual(
            reloaded?.observedInstalledBuild,
            100
        )
    }

    func testPackageVerificationRejectsDifferentManifest()
        throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }

        let store = InAppUpdateEvidenceStore(
            fileURL: root
                .appendingPathComponent(
                    "update-evidence.json"
                )
        )
        let manifest = makeManifest(
            version: "1.0.0",
            build: 100
        )
        let other = makeManifest(
            version: "1.0.1",
            build: 101
        )

        _ = try store.begin(
            currentVersion: "0.9.0",
            currentBuild: 90,
            manifestURL: URL(
                string:
                    "https://updates.blackstock.app/update-manifest.json"
            )!,
            expectedInstallerTeamID:
                "ABC123TEAM"
        )
        _ = try store.recordManifestVerified(
            manifest
        )

        XCTAssertThrowsError(
            try store.recordPackageVerified(other)
        ) { error in
            XCTAssertEqual(
                error as?
                    InAppUpdateEvidenceError,
                .manifestMismatch
            )
        }
    }

    func testInstallerOpenRequiresVerifiedPackage()
        throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }

        let store = InAppUpdateEvidenceStore(
            fileURL: root.appendingPathComponent(
                "update-evidence.json"
            )
        )
        let manifest = makeManifest(
            version: "1.0.0",
            build: 100
        )

        _ = try store.begin(
            currentVersion: "0.9.0",
            currentBuild: 90,
            manifestURL: URL(
                string:
                    "https://updates.blackstock.app/update-manifest.json"
            )!,
            expectedInstallerTeamID: "ABC123TEAM"
        )
        _ = try store.recordManifestVerified(
            manifest
        )

        XCTAssertThrowsError(
            try store.recordInstallerOpened(
                manifest
            )
        ) { error in
            XCTAssertEqual(
                error as? InAppUpdateEvidenceError,
                .packageNotVerified
            )
        }

        let reloaded = try store.load()
        XCTAssertNil(reloaded?.installerOpenedAt)
    }

    func testInstallerOpenRejectsDifferentManifest()
        throws {
        let root = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(at: root)
        }

        let store = InAppUpdateEvidenceStore(
            fileURL: root.appendingPathComponent(
                "update-evidence.json"
            )
        )
        let manifest = makeManifest(
            version: "1.0.0",
            build: 100
        )
        let other = makeManifest(
            version: "1.0.1",
            build: 101
        )

        _ = try store.begin(
            currentVersion: "0.9.0",
            currentBuild: 90,
            manifestURL: URL(
                string:
                    "https://updates.blackstock.app/update-manifest.json"
            )!,
            expectedInstallerTeamID: "ABC123TEAM"
        )
        _ = try store.recordManifestVerified(
            manifest
        )
        _ = try store.recordPackageVerified(
            manifest
        )

        XCTAssertThrowsError(
            try store.recordInstallerOpened(
                other
            )
        ) { error in
            XCTAssertEqual(
                error as? InAppUpdateEvidenceError,
                .manifestMismatch
            )
        }

        let reloaded = try store.load()
        XCTAssertNil(reloaded?.installerOpenedAt)
    }

    private func makeManifest(
        version: String,
        build: Int
    ) -> BlackstockUpdateManifest {
        BlackstockUpdateManifest(
            version: version,
            build: build,
            packageURL: URL(
                string:
                    "https://updates.blackstock.app/Blackstock.pkg"
            )!,
            sha256: String(
                repeating: "a",
                count: 64
            ),
            publishedAt: Date(
                timeIntervalSince1970:
                    1_789_000_000
            ),
            signature: "signature"
        )
    }
}
