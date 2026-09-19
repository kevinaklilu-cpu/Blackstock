#if os(macOS)
import Foundation
import CryptoKit
import BlackstockCore

enum BlackstockUpdateAudit {
    static func recordAvailableUpdate(
        manifest: BlackstockUpdateManifest,
        manifestURL: URL,
        installerTeamID: String,
        bundle: Bundle = .main,
        now: Date = Date()
    ) {
        guard let installed =
                installedVersion(bundle: bundle) else {
            return
        }

        do {
            let store = try productionStore()
            _ = try store.begin(
                currentVersion: installed.version,
                currentBuild: installed.build,
                manifestURL: manifestURL,
                expectedInstallerTeamID:
                    installerTeamID,
                now: now
            )
            _ = try store.recordManifestVerified(
                manifest,
                now: now
            )
        } catch {
            // Evidenz darf die sichere Update-Funktion
            // nicht blockieren. Ein fehlender Nachweis
            // verhindert später lediglich Gate-PASS.
        }
    }

    static func recordVerifiedPackage(
        manifest: BlackstockUpdateManifest,
        now: Date = Date()
    ) {
        do {
            _ = try productionStore()
                .recordPackageVerified(
                    manifest,
                    now: now
                )
        } catch {
            // Siehe recordAvailableUpdate.
        }
    }

    static func recordInstallerOpened(
        manifest: BlackstockUpdateManifest,
        now: Date = Date()
    ) {
        do {
            _ = try productionStore()
                .recordInstallerOpened(
                    manifest,
                    now: now
                )
        } catch {
            // Siehe recordAvailableUpdate.
        }
    }

    static func reconcilePostUpdateLaunch(
        bundle: Bundle = .main,
        now: Date = Date()
    ) {
        guard let installed =
                installedVersion(bundle: bundle),
              let executableURL = bundle.executableURL,
              let executableSHA256 =
                sha256(of: executableURL) else {
            return
        }

        do {
            _ = try productionStore()
                .recordPostUpdateLaunchIfMatching(
                    installedVersion:
                        installed.version,
                    installedBuild:
                        installed.build,
                    installedSourceCommitSHA:
                        installed.sourceCommitSHA,
                    installedExecutableSHA256:
                        executableSHA256,
                    now: now
                )
        } catch {
            // Ein beschädigter Evidenzdatensatz darf
            // den App-Start nicht verhindern.
        }
    }

    static func productionEvidenceURL()
        throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent(
                "Blackstock",
                isDirectory: true
            )
            .appendingPathComponent(
                "Update",
                isDirectory: true
            )
            .appendingPathComponent(
                "update-evidence.json"
            )
    }

    private static func productionStore()
        throws -> InAppUpdateEvidenceStore {
        InAppUpdateEvidenceStore(
            fileURL: try productionEvidenceURL()
        )
    }

    private static func sha256(
        of url: URL
    ) -> String? {
        guard let handle =
                try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

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

    private static func installedVersion(
        bundle: Bundle
    ) -> (
        version: String,
        build: Int,
        sourceCommitSHA: String
    )? {
        guard let version = bundle.object(
            forInfoDictionaryKey:
                "CFBundleShortVersionString"
        ) as? String,
        !version.isEmpty,
        let buildString = bundle.object(
            forInfoDictionaryKey:
                "CFBundleVersion"
        ) as? String,
        let build = Int(buildString),
        build > 0,
        let sourceCommitSHA = bundle.object(
            forInfoDictionaryKey:
                "BlackstockSourceCommitSHA"
        ) as? String,
        sourceCommitSHA.count == 40,
        sourceCommitSHA.allSatisfy({ $0.isHexDigit })
        else {
            return nil
        }
        return (
            version,
            build,
            sourceCommitSHA.lowercased()
        )
    }
}
#endif
