#if os(macOS)
import Foundation
import BlackstockCore

enum BlackstockUpdateInstallationPreflightError:
    Error,
    LocalizedError {
    case missingInstallerTeamID

    var errorDescription: String? {
        switch self {
        case .missingInstallerTeamID:
            return "Für die Installationsprüfung ist keine erwartete Developer-ID-Installer-Team-ID konfiguriert."
        }
    }
}

struct BlackstockUpdateInstallationPreflight: Sendable {
    func verify(
        fileURL: URL,
        manifest: BlackstockUpdateManifest,
        bundle: Bundle = .main
    ) throws {
        try UpdatePackageIntegrityVerifier().verify(
            fileURL: fileURL,
            expectedSHA256: manifest.sha256
        )

        let expectedTeamID = (
            bundle.object(
                forInfoDictionaryKey:
                    "BlackstockUpdateInstallerTeamID"
            ) as? String ?? ""
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !expectedTeamID.isEmpty else {
            throw BlackstockUpdateInstallationPreflightError
                .missingInstallerTeamID
        }

        try BlackstockInstallerPackageVerifier().verify(
            fileURL: fileURL,
            expectedTeamID: expectedTeamID
        )
    }
}
#endif
