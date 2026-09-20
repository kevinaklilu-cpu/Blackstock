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
                installedVersion(bundle: bundle),
              let executableURL = bundle.executableURL,
              let executableSHA256 =
                sha256(of: executableURL) else {
            return
        }

        let installedAppPath = bundle.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let signing = applicationSigningMetadata(
            bundleURL: bundle.bundleURL
        )
        let receipt = installerReceiptMetadata(
            expectedVersion: installed.version
        )

        do {
            let store = try productionStore()
            _ = try store.begin(
                currentVersion: installed.version,
                currentBuild: installed.build,
                currentSourceCommitSHA:
                    installed.sourceCommitSHA,
                currentExecutableSHA256:
                    executableSHA256,
                currentAppPath:
                    installedAppPath,
                currentApplicationTeamID:
                    signing.teamID,
                currentDeveloperIDApplicationVerified:
                    signing.verified,
                currentInstallerReceiptPackageID:
                    receipt.packageID,
                currentInstallerReceiptVersion:
                    receipt.version,
                currentInstallerReceiptInstalledAt:
                    receipt.installedAt,
                currentInstallerReceiptVerified:
                    receipt.verified,
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

        let installedAppPath = bundle.bundleURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let signing = applicationSigningMetadata(
            bundleURL: bundle.bundleURL
        )
        let receipt = installerReceiptMetadata(
            expectedVersion: installed.version
        )

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
                    installedAppPath:
                        installedAppPath,
                    applicationTeamID:
                        signing.teamID,
                    developerIDApplicationVerified:
                        signing.verified,
                    installerReceiptPackageID:
                        receipt.packageID,
                    installerReceiptVersion:
                        receipt.version,
                    installerReceiptInstalledAt:
                        receipt.installedAt,
                    installerReceiptVerified:
                        receipt.verified,
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

    private static func applicationSigningMetadata(
        bundleURL: URL
    ) -> (
        teamID: String,
        verified: Bool
    ) {
        let verifyProcess = Process()
        verifyProcess.executableURL = URL(
            fileURLWithPath: "/usr/bin/codesign"
        )
        verifyProcess.arguments = [
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            bundleURL.path
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
            bundleURL.path
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
            return (
                teamID,
                output.contains(
                    "Authority=Developer ID Application"
                )
            )
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

            let volume = plist["volume"] as? String
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

            return (
                packageID,
                version,
                installedAt,
                packageID == expectedPackageID
                    && version == expectedVersion
                    && volume == "/"
                    && installLocation == "/"
                    && installedAt != Date.distantPast
            )
        } catch {
            return ("", "", .distantPast, false)
        }
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
