#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

requirements = {
    "Sources/BlackstockCore/InAppUpdateEvidence.swift": [
        "InAppUpdateEvidenceStore",
        "recordManifestVerified",
        "recordPackageVerified",
        "recordInstallerOpened",
        "recordPostUpdateLaunchIfMatching",
        "targetSourceCommitSHA",
        "observedInstalledSourceCommitSHA",
        "observedInstalledExecutableSHA256",
        "observedInstalledAppPath",
        "observedApplicationTeamID",
        "observedDeveloperIDApplicationVerified",
        "observedInstallerReceiptPackageID",
        "observedInstallerReceiptVersion",
        "observedInstallerReceiptVerified",
        '"/Applications/Blackstock.app"',
        '"de.blackstock.app"',
        "postUpdateLaunchVerifiedAt",
        "isComplete",
    ],
    "Tests/BlackstockCoreTests/InAppUpdateEvidenceTests.swift": [
        "testVerifiedUpdateCompletesOnlyAfterTargetBuildLaunch",
        "testPackageVerificationRejectsDifferentManifest",
        "testInstallerOpenRequiresVerifiedPackage",
        "testInstallerOpenRejectsDifferentManifest",
        "testPostUpdateLaunchRejectsNonProductionAppPath",
        "observedInstalledAppPath",
        "observedInstallerReceiptVersion",
    ],
    "Sources/BlackstockApp/BlackstockUpdateChecker.swift": [
        "BlackstockUpdateAudit.recordAvailableUpdate",
    ],
    "Sources/BlackstockApp/BlackstockUpdatePackageDownloader.swift": [
        "BlackstockUpdateAudit.recordVerifiedPackage",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "BlackstockUpdateInstallationPreflight()",
        "BlackstockUpdateAudit",
        ".recordVerifiedPackage",
        "BlackstockUpdateAudit.recordInstallerOpened",
        "NSWorkspace.shared.open",
        "Developer-ID-Installer-Team",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "BlackstockUpdateAudit.reconcilePostUpdateLaunch",
    ],
    "Sources/BlackstockApp/BlackstockUpdateInstallationPreflight.swift": [
        "UpdatePackageIntegrityVerifier().verify",
        "BlackstockInstallerPackageVerifier().verify",
        "BlackstockUpdateInstallerTeamID",
        "missingInstallerTeamID",
    ],
    "Sources/BlackstockApp/BlackstockUpdateAudit.swift": [
        "update-evidence.json",
        ".applicationSupportDirectory",
        "recordPostUpdateLaunchIfMatching",
        "CryptoKit",
        "SHA256()",
        "installedExecutableSHA256",
        "installedAppPath",
        "applicationSigningMetadata",
        "installerReceiptMetadata",
        "Authority=Developer ID Application",
        "--pkg-info-plist",
        '"de.blackstock.app"',
        '"pkg-version"',
        '"install-location"',
    ],
    "Build/validate_in_app_update_evidence.py": [
        "observedInstalledVersion",
        "targetSourceCommitSHA",
        "observedInstalledSourceCommitSHA",
        "observedInstalledExecutableSHA256",
        "postUpdateLaunchVerifiedAt",
        "must use a real production host",
        "must not contain embedded credentials",
        "must not contain a fragment",
        'host == "::1"',
        'host.endswith(".local")',
        "id must be a UUID",
        "non-finite JSON number",
        "must be finite",
        "observedInstalledAppPath must be /Applications/Blackstock.app",
        "observedApplicationTeamID must equal expectedInstallerTeamID",
        "observedDeveloperIDApplicationVerified must be true",
        "observedInstallerReceiptPackageID must equal de.blackstock.app",
        "observedInstallerReceiptVersion must equal targetVersion",
        "observedInstallerReceiptVerified must be true",
    ],
    "Sources/BlackstockReleaseVerifier/BlackstockReleaseVerifier.swift": [
        "BLACKSTOCK_RELEASE_VERIFY_PASS",
        "UpdateManifestVerifier",
        "UpdatePackageIntegrityVerifier",
        "InstallerPackageSignatureValidator",
        "stapler",
        "notarytool",
        "spctl",
        "sourceCommitSHA",
        "installedAppSourceCommitSHA",
        "installedAppExecutableSHA256",
        "BlackstockSourceCommitSHA",
    ],
    "Build/validate_production_release_evidence.py": [
        "developerIDInstallerVerified",
        "developerIDApplicationVerified",
        "notaryStatus",
        "gatekeeperInstallerAccepted",
        "gatekeeperApplicationAccepted",
        "installedAppExecutableSHA256",
    ],
    "Build/verify_market_readiness.py": [
        "release.currentVersion",
        "updater.currentVersion",
        "same source update version",
        "release.currentBuild",
        "updater.currentBuild",
        "same source update build",
        '"sourceVersion"',
        '"sourceBuild"',
        "observedApplicationTeamID",
        "observedInstalledAppPath",
        "observedInstallerReceiptPackageID",
        "observedInstallerReceiptVersion",
        "same installed app path",
    ],
    "docs/PRODUCTION_RELEASE_EVIDENCE.md": [
        "Echter Updater-E2E",
        "Updater = FAIL",
    ],
}

errors = []
for relative, markers in requirements.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing updater evidence contract file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(
                f"{relative}: missing updater evidence marker: {marker}"
            )

package = ROOT / "Build/package.sh"
if package.is_file():
    text = package.read_text(encoding="utf-8")
    if "BlackstockReleaseVerifier" in text:
        errors.append(
            "BlackstockReleaseVerifier must remain developer-only and must not be copied into Blackstock.pkg"
        )

if errors:
    print("Updater evidence audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Updater evidence audit passed: production release verification and "
    "the real in-app update evidence chain remain wired and fail-closed."
)
