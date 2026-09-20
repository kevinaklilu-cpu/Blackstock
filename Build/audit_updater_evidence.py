#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

requirements = {
    "Sources/BlackstockCore/UpdateManifest.swift": [
        "ProductionUpdateURLPolicy",
        "ProductionUpdateURLPolicy.allows(",
        "url.user == nil",
        "url.password == nil",
        "url.fragment == nil",
        'host != "::1"',
        '!host.hasSuffix(".local")',
    ],
    "Sources/BlackstockCore/InAppUpdateEvidence.swift": [
        "InAppUpdateEvidenceStore",
        "current = 6",
        "invalidCurrentAppProvenance",
        "currentSourceCommitSHA",
        "currentExecutableSHA256",
        "currentAppPath",
        "currentApplicationTeamID",
        "currentDeveloperIDApplicationVerified",
        "currentInstallerReceiptPackageID",
        "currentInstallerReceiptVersion",
        "currentInstallerReceiptInstalledAt",
        "currentInstallerReceiptVerified",
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
        "observedInstallerReceiptInstalledAt",
        "observedInstallerReceiptVerified",
        '"/Applications/Blackstock.app"',
        '"de.blackstock.app"',
        "postUpdateLaunchVerifiedAt",
        "isComplete",
    ],
    "Tests/BlackstockCoreTests/UpdateManifestTests.swift": [
        "testProductionUpdateURLPolicyRejectsUnsafeURLs",
        "ProductionUpdateURLPolicy.allows(",
        "https://[::1]/Blackstock.pkg",
        "https://updates.blackstock.local/Blackstock.pkg",
    ],
    "Tests/BlackstockCoreTests/InAppUpdateEvidenceTests.swift": [
        "testVerifiedUpdateCompletesOnlyAfterTargetBuildLaunch",
        "testPackageVerificationRejectsDifferentManifest",
        "testInstallerOpenRequiresVerifiedPackage",
        "testInstallerOpenRejectsDifferentManifest",
        "testPostUpdateLaunchRejectsNonProductionAppPath",
        "testBeginRejectsInvalidCurrentAppProvenance",
        "testPostUpdateLaunchRejectsReceiptPredatingInstallerHandoff",
        "observedInstallerReceiptInstalledAt",
        "currentSourceCommitSHA",
        "currentExecutableSHA256",
        "observedInstalledAppPath",
        "observedInstallerReceiptVersion",
    ],
    "Sources/BlackstockApp/BlackstockUpdateChecker.swift": [
        "BlackstockUpdateAudit.recordAvailableUpdate",
        "ProductionUpdateURLPolicy.allows(",
        "let finalURL = http.url",
        "manifestURLMustUseHTTPS",
    ],
    "Sources/BlackstockApp/BlackstockUpdatePackageDownloader.swift": [
        "BlackstockUpdateAudit.recordVerifiedPackage",
        "ProductionUpdateURLPolicy.allows(",
        "let finalURL = http.url",
        "packageURLMustUseHTTPS",
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
        "currentSourceCommitSHA:",
        "currentExecutableSHA256:",
        "currentAppPath:",
        "currentApplicationTeamID:",
        "currentInstallerReceiptPackageID:",
        "installedAppPath",
        "applicationSigningMetadata",
        "installerReceiptMetadata",
        "Authority=Developer ID Application",
        '"--verify"',
        '"--deep"',
        '"--strict"',
        "verifyProcess.terminationStatus == 0",
        "--pkg-info-plist",
        '"de.blackstock.app"',
        '"pkg-version"',
        '"install-time"',
        "installedAtSeconds",
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
        "currentSourceCommitSHA must be a 40-character hexadecimal Git commit SHA",
        "currentExecutableSHA256 must be a 64-character hexadecimal SHA-256",
        "currentAppPath must be /Applications/Blackstock.app",
        "currentApplicationTeamID must equal expectedInstallerTeamID",
        "currentDeveloperIDApplicationVerified must be true",
        "currentInstallerReceiptPackageID must equal de.blackstock.app",
        "currentInstallerReceiptVersion must equal currentVersion",
        "currentInstallerReceiptVerified must be true",
        "observedInstalledAppPath must be /Applications/Blackstock.app",
        "observedApplicationTeamID must equal expectedInstallerTeamID",
        "observedDeveloperIDApplicationVerified must be true",
        "observedInstallerReceiptPackageID must equal de.blackstock.app",
        "observedInstallerReceiptVersion must equal targetVersion",
        "observedInstallerReceiptVerified must be true",
        "currentInstallerReceiptInstalledAt",
        "observedInstallerReceiptInstalledAt",
        "target installer receipt must be newer than source receipt",
        "target installer receipt must not predate installer handoff",
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
        '"sourceInstallerReceiptInstalledAt"',
        '"installerReceiptInstalledAt"',
        '"captureInstallerReceiptInstalledAt"',
        '"sameInstallationReceiptVerified"',
        "same installer receipt installation",
        "TemporaryDirectory",
        "write_snapshot(",
        "require_source_unchanged(",
        '"captureEvidenceSHA256"',
        '"productionReleaseEvidenceSHA256"',
        '"inAppUpdateEvidenceSHA256"',
        "market readiness output must not overwrite an evidence file",
        "NamedTemporaryFile",
        "temporary_output.replace(output_path)",
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
