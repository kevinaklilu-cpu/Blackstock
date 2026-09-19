#if os(macOS)
import Foundation
import BlackstockCore

enum BlackstockInstallerPackageVerificationError: Error, LocalizedError {
    case missingExpectedTeamID
    case pkgutilUnavailable
    case invalidSignature(InstallerPackageSignatureValidationError)

    var errorDescription: String? {
        switch self {
        case .missingExpectedTeamID:
            return "Für den produktiven Updater ist keine erwartete Developer-ID-Installer-Team-ID konfiguriert."
        case .pkgutilUnavailable:
            return "Die macOS-Paketsignatur konnte nicht geprüft werden."
        case .invalidSignature(let error):
            switch error {
            case .invalidExpectedTeamID:
                return "Die konfigurierte Installer-Team-ID ist ungültig."
            case .signatureCheckFailed:
                return "Das Update-Paket besitzt keine von macOS akzeptierte Installer-Signatur."
            case .notDeveloperIDInstaller:
                return "Das Update-Paket ist nicht mit einer Developer-ID-Installer-Identität signiert."
            case .teamIDMismatch:
                return "Die Signatur des Update-Pakets gehört nicht zur erwarteten Blackstock-Team-ID."
            }
        }
    }
}

struct BlackstockInstallerPackageVerifier: Sendable {
    func verify(
        fileURL: URL,
        expectedTeamID: String
    ) throws {
        let teamID = expectedTeamID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !teamID.isEmpty else {
            throw BlackstockInstallerPackageVerificationError
                .missingExpectedTeamID
        }

        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/sbin/pkgutil"
        )
        process.arguments = [
            "--check-signature",
            fileURL.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw BlackstockInstallerPackageVerificationError
                .pkgutilUnavailable
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(
            data: data,
            encoding: .utf8
        ) ?? ""

        do {
            try InstallerPackageSignatureValidator().validate(
                pkgutilOutput: output,
                exitStatus: process.terminationStatus,
                expectedTeamID: teamID
            )
        } catch let error as InstallerPackageSignatureValidationError {
            throw BlackstockInstallerPackageVerificationError
                .invalidSignature(error)
        }
    }
}
#endif
