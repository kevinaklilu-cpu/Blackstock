import Foundation

public enum InstallerPackageSignatureValidationError: Error, Sendable, Equatable {
    case invalidExpectedTeamID
    case signatureCheckFailed(Int32)
    case notDeveloperIDInstaller
    case teamIDMismatch
}

public struct InstallerPackageSignatureValidator: Sendable {
    public init() {}

    public func validate(
        pkgutilOutput: String,
        exitStatus: Int32,
        expectedTeamID: String
    ) throws {
        let teamID = expectedTeamID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !teamID.isEmpty,
              teamID.allSatisfy({
                  $0.isASCII
                  && ($0.isLetter || $0.isNumber)
              }) else {
            throw InstallerPackageSignatureValidationError
                .invalidExpectedTeamID
        }

        guard exitStatus == 0 else {
            throw InstallerPackageSignatureValidationError
                .signatureCheckFailed(exitStatus)
        }

        guard pkgutilOutput.localizedCaseInsensitiveContains(
            "Developer ID Installer"
        ) else {
            throw InstallerPackageSignatureValidationError
                .notDeveloperIDInstaller
        }

        guard pkgutilOutput.contains("(\(teamID))") else {
            throw InstallerPackageSignatureValidationError.teamIDMismatch
        }
    }
}
