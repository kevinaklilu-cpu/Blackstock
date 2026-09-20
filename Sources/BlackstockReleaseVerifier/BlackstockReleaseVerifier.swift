import BlackstockCore
import CryptoKit
import Foundation

private enum ReleaseVerifierError: Error, LocalizedError {
    case missingArgument(String)
    case invalidInteger(String)
    case invalidURL(String)
    case httpStatus(Int)
    case noUpdateAvailable
    case commandFailed(String, Int32, String)
    case appIdentityMismatch
    case installedAppVersionMismatch
    case installedAppSourceCommitMismatch
    case missingCaptureEntitlements
    case incompleteNotaryArguments
    case notarizationNotAccepted(String)
    case incompleteVerifiedSnapshotArguments

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Fehlendes Argument: \(name)"
        case .invalidInteger(let value):
            return "Ungültige Ganzzahl: \(value)"
        case .invalidURL(let value):
            return "Ungültige HTTPS-URL: \(value)"
        case .httpStatus(let status):
            return "Remote-Endpunkt antwortete mit HTTP \(status)."
        case .noUpdateAvailable:
            return "Das Manifest beschreibt kein Update gegenüber der angegebenen Ausgangsversion."
        case .commandFailed(let command, let status, let output):
            return "\(command) schlug mit Status \(status) fehl: \(output)"
        case .appIdentityMismatch:
            return "Die installierte App ist nicht mit der erwarteten Developer-ID-Application-Team-ID signiert."
        case .installedAppVersionMismatch:
            return "Die installierte App entspricht nicht exakt Manifest-Version und -Build."
        case .installedAppSourceCommitMismatch:
            return "Die installierte App stammt nicht aus dem im signierten Manifest gebundenen Source-Commit."
        case .missingCaptureEntitlements:
            return "Der installierten Produktions-App fehlen die Hardened-Runtime-Entitlements für Kamera oder Audioeingang."
        case .incompleteNotaryArguments:
            return "Notary-Submission-ID benötigt entweder ein Keychain-Profil oder vollständig konfigurierte API-Key-Zugangsdaten."
        case .notarizationNotAccepted(let status):
            return "Apple-Notarisierung ist nicht Accepted, sondern \(status)."
        case .incompleteVerifiedSnapshotArguments:
            return "Verifizierter Release-Snapshot benötigt Manifest- und Paketdatei gemeinsam."
        }
    }
}

private struct CommandResult {
    let status: Int32
    let output: String
}

private struct ReleaseVerificationEvidence: Codable {
    let schemaVersion: Int
    let verifiedAt: Date
    let manifestURL: URL
    let packageURL: URL
    let currentVersion: String
    let currentBuild: Int
    let targetVersion: String
    let targetBuild: Int
    let packageSHA256: String
    let sourceCommitSHA: String
    let installerTeamID: String
    let manifestSignatureVerified: Bool
    let updateAvailabilityVerified: Bool
    let packageHashVerified: Bool
    let developerIDInstallerVerified: Bool
    let staplerValidated: Bool
    let gatekeeperInstallerAccepted: Bool
    let installedAppPath: String?
    let installedAppVersion: String?
    let installedAppBuild: Int?
    let installedAppSourceCommitSHA: String?
    let installedAppExecutableSHA256: String?
    let cameraEntitlementVerified: Bool?
    let audioInputEntitlementVerified: Bool?
    let developerIDApplicationVerified: Bool?
    let gatekeeperApplicationAccepted: Bool?
    let notarySubmissionID: String?
    let notaryStatus: String?
}

@main
private struct BlackstockReleaseVerifierMain {
    static func main() async {
        do {
            let arguments = try Arguments.parse(
                Array(CommandLine.arguments.dropFirst())
            )
            let evidence = try await verify(arguments)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(evidence)

            if let output = arguments.outputURL {
                try FileManager.default.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: output, options: [.atomic])
                print("BLACKSTOCK_RELEASE_VERIFY_PASS")
                print(output.path)
            } else {
                print("BLACKSTOCK_RELEASE_VERIFY_PASS")
                print(String(decoding: data, as: UTF8.self))
            }
        } catch {
            fputs(
                "BLACKSTOCK_RELEASE_VERIFY_FAIL: \(error.localizedDescription)\n",
                stderr
            )
            exit(1)
        }
    }

    private static func verify(
        _ arguments: Arguments
    ) async throws -> ReleaseVerificationEvidence {
        let manifestData: Data
        if let verifiedManifestInputURL =
                arguments.verifiedManifestInputURL {
            manifestData = try Data(
                contentsOf: verifiedManifestInputURL
            )
        } else {
            let (downloadedManifestData, manifestResponse) =
                try await URLSession.shared.data(
                    from: arguments.manifestURL
                )
            try requireHTTPSResponse(manifestResponse)
            manifestData = downloadedManifestData
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            BlackstockUpdateManifest.self,
            from: manifestData
        )

        try UpdateManifestVerifier().verify(
            manifest,
            publicKeyBase64: arguments.publicKeyBase64
        )

        guard isProductionHTTPSURL(manifest.packageURL) else {
            throw ReleaseVerifierError.invalidURL(
                manifest.packageURL.absoluteString
            )
        }

        switch try UpdateManifestVerifier().availability(
            manifest: manifest,
            currentVersion: arguments.currentVersion,
            currentBuild: arguments.currentBuild
        ) {
        case .upToDate:
            throw ReleaseVerifierError.noUpdateAvailable
        case .updateAvailable:
            break
        }

        let packageURL: URL
        var downloadedPackageURLForCleanup: URL?
        if let verifiedPackageInputURL =
                arguments.verifiedPackageInputURL {
            packageURL = verifiedPackageInputURL
        } else {
            let (downloadedURL, packageResponse) =
                try await URLSession.shared.download(
                    from: manifest.packageURL
                )
            try requireHTTPSResponse(packageResponse)

            let temporaryPackageURL =
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "Blackstock-Release-\(UUID().uuidString)"
                    )
                    .appendingPathExtension("pkg")
            try? FileManager.default.removeItem(
                at: temporaryPackageURL
            )
            try FileManager.default.moveItem(
                at: downloadedURL,
                to: temporaryPackageURL
            )
            downloadedPackageURLForCleanup =
                temporaryPackageURL
            packageURL = temporaryPackageURL
        }
        defer {
            if let downloadedPackageURLForCleanup {
                try? FileManager.default.removeItem(
                    at: downloadedPackageURLForCleanup
                )
            }
        }

        try UpdatePackageIntegrityVerifier().verify(
            fileURL: packageURL,
            expectedSHA256: manifest.sha256
        )

        let pkgutil = try run(
            "/usr/sbin/pkgutil",
            ["--check-signature", packageURL.path]
        )
        try InstallerPackageSignatureValidator().validate(
            pkgutilOutput: pkgutil.output,
            exitStatus: pkgutil.status,
            expectedTeamID: arguments.installerTeamID
        )

        _ = try requireSuccessful(
            run(
                "/usr/bin/xcrun",
                ["stapler", "validate", packageURL.path]
            ),
            command: "xcrun stapler validate"
        )
        _ = try requireSuccessful(
            run(
                "/usr/sbin/spctl",
                [
                    "--assess",
                    "--type", "install",
                    "--verbose=2",
                    packageURL.path
                ]
            ),
            command: "spctl --type install"
        )

        var applicationVerified: Bool?
        var applicationGatekeeperAccepted: Bool?
        var installedAppVersion: String?
        var installedAppBuild: Int?
        var installedAppSourceCommitSHA: String?
        var installedAppExecutableSHA256: String?
        var cameraEntitlementVerified: Bool?
        var audioInputEntitlementVerified: Bool?
        if let appURL = arguments.installedAppURL {
            _ = try requireSuccessful(
                run(
                    "/usr/bin/codesign",
                    [
                        "--verify",
                        "--deep",
                        "--strict",
                        "--verbose=2",
                        appURL.path
                    ]
                ),
                command: "codesign --verify"
            )

            let identity = try requireSuccessful(
                run(
                    "/usr/bin/codesign",
                    [
                        "--display",
                        "--verbose=4",
                        appURL.path
                    ]
                ),
                command: "codesign --display"
            )
            guard identity.output.contains(
                "Authority=Developer ID Application"
            ),
            identity.output.contains(
                "TeamIdentifier=\(arguments.installerTeamID)"
            ) else {
                throw ReleaseVerifierError.appIdentityMismatch
            }
            applicationVerified = true

            let infoURL = appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist")
            let infoData = try Data(contentsOf: infoURL)
            guard let info = try PropertyListSerialization
                    .propertyList(
                        from: infoData,
                        options: [],
                        format: nil
                    ) as? [String: Any],
                  let appVersion =
                    info["CFBundleShortVersionString"]
                        as? String,
                  let appBuildString =
                    info["CFBundleVersion"]
                        as? String,
                  let appBuild = Int(appBuildString),
                  appVersion == manifest.version,
                  appBuild == manifest.build else {
                throw ReleaseVerifierError
                    .installedAppVersionMismatch
            }
            installedAppVersion = appVersion
            installedAppBuild = appBuild

            guard let appSourceCommitSHA =
                    info["BlackstockSourceCommitSHA"]
                        as? String,
                  appSourceCommitSHA.count == 40,
                  appSourceCommitSHA.allSatisfy({
                      $0.isHexDigit
                  }),
                  appSourceCommitSHA.lowercased()
                    == manifest.sourceCommitSHA.lowercased()
            else {
                throw ReleaseVerifierError
                    .installedAppSourceCommitMismatch
            }
            installedAppSourceCommitSHA =
                appSourceCommitSHA.lowercased()

            guard let executableName =
                    info["CFBundleExecutable"] as? String,
                  !executableName.isEmpty else {
                throw ReleaseVerifierError.installedAppVersionMismatch
            }
            let executableURL = appURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .appendingPathComponent(executableName)
            installedAppExecutableSHA256 =
                try sha256(of: executableURL)

            let entitlements = try requireSuccessful(
                run(
                    "/usr/bin/codesign",
                    [
                        "--display",
                        "--entitlements", ":-",
                        appURL.path
                    ]
                ),
                command: "codesign --display --entitlements"
            )
            let hasCameraEntitlement =
                entitlements.output.contains(
                    "com.apple.security.device.camera"
                )
                && entitlementIsTrue(
                    "com.apple.security.device.camera",
                    in: entitlements.output
                )
            let hasAudioInputEntitlement =
                entitlements.output.contains(
                    "com.apple.security.device.audio-input"
                )
                && entitlementIsTrue(
                    "com.apple.security.device.audio-input",
                    in: entitlements.output
                )
            guard hasCameraEntitlement,
                  hasAudioInputEntitlement else {
                throw ReleaseVerifierError
                    .missingCaptureEntitlements
            }
            cameraEntitlementVerified = true
            audioInputEntitlementVerified = true

            _ = try requireSuccessful(
                run(
                    "/usr/sbin/spctl",
                    [
                        "--assess",
                        "--type", "execute",
                        "--verbose=2",
                        appURL.path
                    ]
                ),
                command: "spctl --type execute"
            )
            applicationGatekeeperAccepted = true
        }

        let notaryStatus = try verifyNotaryIfConfigured(
            arguments
        )

        if let verifiedManifestOutputURL =
                arguments.verifiedManifestOutputURL {
            try persistVerifiedManifest(
                manifestData,
                to: verifiedManifestOutputURL
            )
        }
        if let verifiedPackageOutputURL =
                arguments.verifiedPackageOutputURL {
            try persistVerifiedPackage(
                from: packageURL,
                to: verifiedPackageOutputURL,
                expectedSHA256: manifest.sha256
            )
        }

        return ReleaseVerificationEvidence(
            schemaVersion: 3,
            verifiedAt: Date(),
            manifestURL: arguments.manifestURL,
            packageURL: manifest.packageURL,
            currentVersion: arguments.currentVersion,
            currentBuild: arguments.currentBuild,
            targetVersion: manifest.version,
            targetBuild: manifest.build,
            packageSHA256: manifest.sha256,
            sourceCommitSHA:
                manifest.sourceCommitSHA.lowercased(),
            installerTeamID: arguments.installerTeamID,
            manifestSignatureVerified: true,
            updateAvailabilityVerified: true,
            packageHashVerified: true,
            developerIDInstallerVerified: true,
            staplerValidated: true,
            gatekeeperInstallerAccepted: true,
            installedAppPath: arguments.installedAppURL?.path,
            installedAppVersion: installedAppVersion,
            installedAppBuild: installedAppBuild,
            installedAppSourceCommitSHA:
                installedAppSourceCommitSHA,
            installedAppExecutableSHA256:
                installedAppExecutableSHA256,
            cameraEntitlementVerified:
                cameraEntitlementVerified,
            audioInputEntitlementVerified:
                audioInputEntitlementVerified,
            developerIDApplicationVerified: applicationVerified,
            gatekeeperApplicationAccepted:
                applicationGatekeeperAccepted,
            notarySubmissionID: arguments.notarySubmissionID,
            notaryStatus: notaryStatus
        )
    }

    private static func verifyNotaryIfConfigured(
        _ arguments: Arguments
    ) throws -> String? {
        let id = arguments.notarySubmissionID
        let profile = arguments.notaryKeychainProfile
        let keyPath = arguments.notaryKeyPath
        let keyID = arguments.notaryKeyID
        let issuer = arguments.notaryIssuer

        let apiValues = [keyPath, keyID, issuer]
        let apiConfigured = apiValues.allSatisfy { $0 != nil }
        let apiPartiallyConfigured =
            apiValues.contains { $0 != nil }
                && !apiConfigured

        if apiPartiallyConfigured
            || (profile != nil && apiConfigured)
            || (id == nil && (profile != nil || apiConfigured))
            || (id != nil && profile == nil && !apiConfigured) {
            throw ReleaseVerifierError.incompleteNotaryArguments
        }
        guard let id else {
            return nil
        }

        var notaryArguments = [
            "notarytool",
            "info",
            id
        ]
        if let profile {
            notaryArguments += [
                "--keychain-profile",
                profile
            ]
        } else if let keyPath,
                  let keyID,
                  let issuer {
            notaryArguments += [
                "--key",
                keyPath,
                "--key-id",
                keyID,
                "--issuer",
                issuer
            ]
        } else {
            throw ReleaseVerifierError.incompleteNotaryArguments
        }
        notaryArguments += [
            "--output-format",
            "json"
        ]

        let result = try requireSuccessful(
            run(
                "/usr/bin/xcrun",
                notaryArguments
            ),
            command: "xcrun notarytool info"
        )
        let data = Data(result.output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any],
              let status = dictionary["status"] as? String else {
            throw ReleaseVerifierError.notarizationNotAccepted(
                "UNLESBAR"
            )
        }
        guard status.caseInsensitiveCompare("Accepted") == .orderedSame else {
            throw ReleaseVerifierError.notarizationNotAccepted(
                status
            )
        }
        return status
    }

    private static func entitlementIsTrue(
        _ key: String,
        in output: String
    ) -> Bool {
        let escaped = NSRegularExpression
            .escapedPattern(for: key)
        let pattern =
            "<key>\\s*\(escaped)\\s*</key>\\s*<true\\s*/>"
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(
            output.startIndex..<output.endIndex,
            in: output
        )
        return expression.firstMatch(
            in: output,
            options: [],
            range: range
        ) != nil
    }

    private static func requireHTTPSResponse(
        _ response: URLResponse
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ReleaseVerifierError.httpStatus(-1)
        }
        guard 200..<300 ~= http.statusCode else {
            throw ReleaseVerifierError.httpStatus(
                http.statusCode
            )
        }
        guard let finalURL = http.url,
              isProductionHTTPSURL(finalURL) else {
            throw ReleaseVerifierError.invalidURL(
                http.url?.absoluteString ?? "UNBEKANNT"
            )
        }
    }

    private static func isProductionHTTPSURL(
        _ url: URL
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.fragment == nil else {
            return false
        }
        return host != "localhost"
            && !host.hasPrefix("127.")
            && !host.hasSuffix(".invalid")
            && !host.hasSuffix(".example")
            && !host.hasSuffix(".test")
    }

    private static func persistVerifiedManifest(
        _ data: Data,
        to destinationURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(
            to: destinationURL,
            options: [.atomic]
        )
        guard try Data(contentsOf: destinationURL) == data else {
            throw ReleaseVerifierError.commandFailed(
                "persist verified manifest",
                -1,
                "Persistierte Manifestbytes stimmen nicht mit dem verifizierten Snapshot überein."
            )
        }
    }

    private static func persistVerifiedPackage(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedSHA256: String
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
            )
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        try? fileManager.removeItem(at: temporaryURL)
        try fileManager.copyItem(
            at: sourceURL,
            to: temporaryURL
        )
        try UpdatePackageIntegrityVerifier().verify(
            fileURL: temporaryURL,
            expectedSHA256: expectedSHA256
        )

        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(
            at: temporaryURL,
            to: destinationURL
        )
    }

    private static func sha256(
        of url: URL
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(
                upToCount: 1_048_576
            ) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func run(
        _ executable: String,
        _ arguments: [String]
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: executable
        )
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            status: process.terminationStatus,
            output: String(
                decoding: data,
                as: UTF8.self
            )
        )
    }

    private static func requireSuccessful(
        _ result: CommandResult,
        command: String
    ) throws -> CommandResult {
        guard result.status == 0 else {
            throw ReleaseVerifierError.commandFailed(
                command,
                result.status,
                result.output
            )
        }
        return result
    }
}

private struct Arguments {
    let manifestURL: URL
    let publicKeyBase64: String
    let installerTeamID: String
    let currentVersion: String
    let currentBuild: Int
    let installedAppURL: URL?
    let notarySubmissionID: String?
    let notaryKeychainProfile: String?
    let notaryKeyPath: String?
    let notaryKeyID: String?
    let notaryIssuer: String?
    let verifiedManifestInputURL: URL?
    let verifiedPackageInputURL: URL?
    let verifiedManifestOutputURL: URL?
    let verifiedPackageOutputURL: URL?
    let outputURL: URL?

    static func parse(
        _ raw: [String]
    ) throws -> Arguments {
        var values: [String: String] = [:]
        var index = 0
        while index < raw.count {
            let key = raw[index]
            guard key.hasPrefix("--"),
                  raw.indices.contains(index + 1) else {
                throw ReleaseVerifierError.missingArgument(
                    key
                )
            }
            values[key] = raw[index + 1]
            index += 2
        }

        let manifestString = try required(
            "--manifest-url",
            values
        )
        guard let manifestURL = URL(string: manifestString),
              manifestURL.scheme?.lowercased() == "https" else {
            throw ReleaseVerifierError.invalidURL(
                manifestString
            )
        }

        let buildString = try required(
            "--current-build",
            values
        )
        guard let currentBuild = Int(buildString),
              currentBuild > 0 else {
            throw ReleaseVerifierError.invalidInteger(
                buildString
            )
        }

        let hasVerifiedManifestInput =
            values["--verified-manifest-input"] != nil
        let hasVerifiedPackageInput =
            values["--verified-package-input"] != nil
        guard hasVerifiedManifestInput
                == hasVerifiedPackageInput else {
            throw ReleaseVerifierError
                .incompleteVerifiedSnapshotArguments
        }

        return Arguments(
            manifestURL: manifestURL,
            publicKeyBase64: try required(
                "--public-key-base64",
                values
            ),
            installerTeamID: try required(
                "--installer-team-id",
                values
            ),
            currentVersion: try required(
                "--current-version",
                values
            ),
            currentBuild: currentBuild,
            installedAppURL: values["--installed-app"].map {
                URL(fileURLWithPath: $0)
            },
            notarySubmissionID:
                values["--notary-submission-id"],
            notaryKeychainProfile:
                values["--notary-keychain-profile"],
            notaryKeyPath:
                values["--notary-key"],
            notaryKeyID:
                values["--notary-key-id"],
            notaryIssuer:
                values["--notary-issuer"],
            verifiedManifestInputURL:
                values["--verified-manifest-input"].map {
                    URL(fileURLWithPath: $0)
                },
            verifiedPackageInputURL:
                values["--verified-package-input"].map {
                    URL(fileURLWithPath: $0)
                },
            verifiedManifestOutputURL:
                values["--verified-manifest-output"].map {
                    URL(fileURLWithPath: $0)
                },
            verifiedPackageOutputURL:
                values["--verified-package-output"].map {
                    URL(fileURLWithPath: $0)
                },
            outputURL: values["--output"].map {
                URL(fileURLWithPath: $0)
            }
        )
    }

    private static func required(
        _ key: String,
        _ values: [String: String]
    ) throws -> String {
        guard let value = values[key],
              !value.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            throw ReleaseVerifierError.missingArgument(key)
        }
        return value
    }
}
