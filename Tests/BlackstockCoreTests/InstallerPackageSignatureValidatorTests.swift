import XCTest
@testable import BlackstockCore

final class InstallerPackageSignatureValidatorTests: XCTestCase {
    func testAcceptsExpectedDeveloperIDInstallerTeam() throws {
        let output = """
        Package "Blackstock.pkg":
           Status: signed by a certificate trusted by macOS
           Certificate Chain:
            1. Developer ID Installer: Blackstock GmbH (ABCDE12345)
        """

        XCTAssertNoThrow(
            try InstallerPackageSignatureValidator().validate(
                pkgutilOutput: output,
                exitStatus: 0,
                expectedTeamID: "ABCDE12345"
            )
        )
    }

    func testRejectsWrongInstallerTeam() {
        let output = """
        Package "Blackstock.pkg":
           Certificate Chain:
            1. Developer ID Installer: Other Company (ZZZZZ99999)
        """

        XCTAssertThrowsError(
            try InstallerPackageSignatureValidator().validate(
                pkgutilOutput: output,
                exitStatus: 0,
                expectedTeamID: "ABCDE12345"
            )
        ) {
            XCTAssertEqual(
                $0 as? InstallerPackageSignatureValidationError,
                .teamIDMismatch
            )
        }
    }

    func testRejectsNonDeveloperIDInstallerSignature() {
        let output = """
        Package "Blackstock.pkg":
           Certificate Chain:
            1. Mac Developer Installer: Example (ABCDE12345)
        """

        XCTAssertThrowsError(
            try InstallerPackageSignatureValidator().validate(
                pkgutilOutput: output,
                exitStatus: 0,
                expectedTeamID: "ABCDE12345"
            )
        ) {
            XCTAssertEqual(
                $0 as? InstallerPackageSignatureValidationError,
                .notDeveloperIDInstaller
            )
        }
    }

    func testRejectsFailedPkgutilCheck() {
        XCTAssertThrowsError(
            try InstallerPackageSignatureValidator().validate(
                pkgutilOutput: "",
                exitStatus: 1,
                expectedTeamID: "ABCDE12345"
            )
        ) {
            XCTAssertEqual(
                $0 as? InstallerPackageSignatureValidationError,
                .signatureCheckFailed(1)
            )
        }
    }
}
