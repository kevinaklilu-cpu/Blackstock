#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

requirements = {
    ".github/workflows/production-release.yml": [
        "workflow_dispatch:",
        "BLACKSTOCK_APP_CERT_P12_BASE64",
        "BLACKSTOCK_INSTALLER_CERT_P12_BASE64",
        "BLACKSTOCK_CODESIGN_IDENTITY",
        "BLACKSTOCK_INSTALLER_IDENTITY",
        "BLACKSTOCK_NOTARY_KEY_P8_BASE64",
        "BLACKSTOCK_NOTARY_KEY_ID",
        "BLACKSTOCK_NOTARY_ISSUER",
        "BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64",
        "BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64",
        "Verify update signing key pair",
        "Build/verify_update_key_pair.swift",
        "BLACKSTOCK_INCLUDE_E2E_SMOKE: \"0\"",
        "BLACKSTOCK_PRODUCTION_RELEASE: \"1\"",
        "Build/package.sh",
        "generate_update_manifest.swift",
        "--source-commit-sha",
        "BLACKSTOCK_SOURCE_COMMIT_SHA",
        "notary-response.json",
        "Developer-only helper leaked into production package.",
        "actions/upload-artifact@v4",
        "Cleanup signing material",
    ],
    ".github/workflows/verify-published-release.yml": [
        "workflow_dispatch:",
        "Verify remote manifest and package before installation",
        "BlackstockReleaseVerifier",
        "validate_production_release_evidence.py",
        "--installed-app \"/Applications/Blackstock.app\"",
        "--notary-key",
        "--notary-key-id",
        "--notary-issuer",
        "curl",
        "--proto '=https'",
        "sudo installer",
        "Launch verified production app",
        "actions/upload-artifact@v4",
    ],
    "Build/package.sh": [
        "BLACKSTOCK_NOTARY_KEY_PATH",
        "BLACKSTOCK_NOTARY_KEY_ID",
        "BLACKSTOCK_NOTARY_ISSUER",
        "BLACKSTOCK_NOTARY_EVIDENCE_PATH",
        "BLACKSTOCK_PRODUCTION_RELEASE",
        "Build/validate_production_package_config.py",
        "Production release must not include the CI-only E2E helper.",
        "Build/validate_production_package_config.py",
        "Production release requires notarization credentials.",
        "--output-format json",
        "Notarization status is not Accepted",
    ],
    "Sources/BlackstockReleaseVerifier/BlackstockReleaseVerifier.swift": [
        "--notary-key",
        "--notary-key-id",
        "--notary-issuer",
        "installedAppVersion",
        "installedAppBuild",
        "installedAppVersionMismatch",
        "sourceCommitSHA",
        "installedAppSourceCommitSHA",
        "BlackstockSourceCommitSHA",
        "cameraEntitlementVerified",
        "audioInputEntitlementVerified",
        "missingCaptureEntitlements",
        "com.apple.security.device.camera",
        "com.apple.security.device.audio-input",
    ],
    "Build/validate_production_release_evidence.py": [
        "installedAppVersion",
        "installedAppBuild",
        "sourceCommitSHA",
        "installedAppSourceCommitSHA",
        "cameraEntitlementVerified",
        "audioInputEntitlementVerified",
        "/Applications/Blackstock.app",
    ],
}

errors = []
for relative, markers in requirements.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing production release workflow file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing required marker: {marker}")

production = (ROOT / ".github/workflows/production-release.yml").read_text(
    encoding="utf-8"
)
if "BLACKSTOCK_INCLUDE_E2E_SMOKE: \"1\"" in production:
    errors.append(
        "production release workflow must never package the CI-only E2E helper"
    )
if "pull_request:" in production or "push:" in production:
    errors.append(
        "production release workflow must remain explicit workflow_dispatch only"
    )

verify = (ROOT / ".github/workflows/verify-published-release.yml").read_text(
    encoding="utf-8"
)
if "pull_request:" in verify or "push:" in verify:
    errors.append(
        "published release verification must remain explicit workflow_dispatch only"
    )

if errors:
    print("Production release workflow audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Production release workflow audit passed: signing/notarization and "
    "published-release verification remain explicit, secret-backed and "
    "separate from synthetic canonical CI."
)
