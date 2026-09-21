#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

requirements = {
    ".github/workflows/production-release.yml": [
        "workflow_dispatch:",
        "runs-on: macos-26",
        "DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer",
        "Pinned macOS toolchain guard",
        "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
        "persist-credentials: false",
        "BLACKSTOCK_APP_CERT_P12_BASE64",
        "BLACKSTOCK_INSTALLER_CERT_P12_BASE64",
        "BLACKSTOCK_CODESIGN_IDENTITY",
        "BLACKSTOCK_INSTALLER_IDENTITY",
        "BLACKSTOCK_NOTARY_KEY_P8_BASE64",
        "BLACKSTOCK_NOTARY_KEY_ID",
        "BLACKSTOCK_NOTARY_ISSUER",
        "BLACKSTOCK_UPDATE_PRIVATE_KEY_BASE64",
        "BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64",
        "BLACKSTOCK_GOOGLE_OAUTH_CLIENT_ID",
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
        "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
        "Cleanup signing material",
        "https://github.com/${{ github.repository }}/releases/latest/download/update-manifest.json",
        "https://github.com/${{ github.repository }}/releases/download/v${{ inputs.version }}-build.${{ inputs.build }}/Blackstock.pkg",
        "contents: write",
        "releases/latest/download/update-manifest.json",
        "BLACKSTOCK_RELEASE_TAG",
        "Resolve previous production baseline",
        "Publish production GitHub Release",
        "gh release create",
        "--latest",
        "Wait for published update endpoint",
        "Verify published release and installed production app",
        "validate_production_release_evidence.py",
        "Roll back failed published release",
        "gh release delete",
    ],
    ".github/workflows/verify-published-release.yml": [
        "workflow_dispatch:",
        "runs-on: macos-26",
        "DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer",
        "Pinned macOS toolchain guard",
        "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
        "persist-credentials: false",
        "Verify remote manifest and package before installation",
        "BlackstockReleaseVerifier",
        "validate_production_release_evidence.py",
        "--installed-app \"/Applications/Blackstock.app\"",
        "--notary-key",
        "--notary-key-id",
        "--notary-issuer",
        "preinstall-release-evidence.json",
        "manifestSignatureVerified",
        "packageHashVerified",
        "--verified-manifest-output",
        "--verified-package-output",
        "--verified-manifest-input",
        "--verified-package-input",
        "verified-update-manifest.json",
        "Blackstock-production.pkg",
        "post-install evidence diverged from pre-install verified snapshot",
        "Install exact package verified by release verifier",
        "sudo installer",
        "Launch verified production app",
        "parsed.username",
        "parsed.fragment",
        "host.endswith(\".local\")",
        "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
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
        "CFBundleIconFile",
        "Blackstock.icns",
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
        "installedAppExecutableSHA256",
        "installedAppArchitectureMismatch",
        "/usr/bin/lipo",
        "\"-archs\"",
        "architectures.contains(\"arm64\")",
        "architectures.contains(\"x86_64\")",
        "BlackstockSourceCommitSHA",
        "CryptoKit",
        "sha256(of:",
        "cameraEntitlementVerified",
        "audioInputEntitlementVerified",
        "missingCaptureEntitlements",
        "com.apple.security.device.camera",
        "com.apple.security.device.audio-input",
        "isProductionHTTPSURL(manifest.packageURL)",
        "isProductionHTTPSURL(finalURL)",
        "--verified-manifest-input",
        "--verified-package-input",
        "--verified-manifest-output",
        "--verified-package-output",
        "incompleteVerifiedSnapshotArguments",
        "persistVerifiedManifest(",
        "persistVerifiedPackage(",
        "expectedSHA256: manifest.sha256",
        "isProductionHTTPSURL(manifestURL)",
        "ProductionUpdateURLPolicy.allows(url)",
    ],
    "Sources/BlackstockCore/UpdateManifest.swift": [
        "ProductionUpdateURLPolicy",
        "ProductionUpdateURLPolicy.allows(",
        "url.user == nil",
        "url.password == nil",
        "url.fragment == nil",
        'host != "::1"',
        '!host.hasSuffix(".local")',
        '!host.hasSuffix(".invalid")',
        '!host.hasSuffix(".example")',
        '!host.hasSuffix(".test")',
    ],
    "Build/generate_update_manifest.swift": [
        "isProductionHTTPSURL(packageURL)",
        "url.user == nil",
        "url.password == nil",
        "url.fragment == nil",
        "host != \"::1\"",
        "!host.hasSuffix(\".local\")",
        "!host.hasSuffix(\".invalid\")",
        "!host.hasSuffix(\".example\")",
        "!host.hasSuffix(\".test\")",
    ],
    "Build/validate_production_package_config.py": [
        "\".local\"",
        "parsed.username",
        "parsed.password",
        "parsed.fragment",
        "host == \"::1\"",
    ],
    "Build/validate_production_release_evidence.py": [
        "installedAppVersion",
        "installedAppBuild",
        "sourceCommitSHA",
        "installedAppSourceCommitSHA",
        "installedAppExecutableSHA256",
        "cameraEntitlementVerified",
        "audioInputEntitlementVerified",
        "/Applications/Blackstock.app",
        "non-finite JSON number",
        "parsed.username",
        "parsed.password",
        "parsed.fragment",
        'host == "::1"',
        'host.endswith(".local")',
        "notarySubmissionID must be a UUID",
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
if "\n      manifest_url:\n" in production or "\n      package_url:\n" in production:
    errors.append(
        "production release workflow must derive canonical GitHub Release update URLs instead of asking for manual endpoint inputs"
    )
if "BLACKSTOCK_MANIFEST_URL: https://github.com/${{ github.repository }}/releases/latest/download/update-manifest.json" not in production:
    errors.append(
        "production workflow must derive the stable manifest URL from the current GitHub repository"
    )
if "BLACKSTOCK_PACKAGE_URL: https://github.com/${{ github.repository }}/releases/download/v${{ inputs.version }}-build.${{ inputs.build }}/Blackstock.pkg" not in production:
    errors.append(
        "production workflow must derive an immutable version/build package URL from the current GitHub repository"
    )
if "contents: write" not in production:
    errors.append(
        "production release workflow needs contents: write to publish GitHub Releases"
    )
if "releases/latest/download/update-manifest.json" not in production:
    errors.append(
        "production app must be built with the stable latest-release manifest endpoint"
    )

if "BLACKSTOCK_GOOGLE_OAUTH_CLIENT_SECRET" in production:
    errors.append(
        "desktop OAuth client_secret must not be required or injected into the production package workflow"
    )
if "BLACKSTOCK_INCLUDE_E2E_SMOKE: \"1\"" in production:
    errors.append(
        "production release workflow must never package the CI-only E2E helper"
    )
if "pull_request:" in production or "push:" in production:
    errors.append(
        "production release workflow must remain explicit workflow_dispatch only"
    )

for marker, expected in [
    ("- name: Validate release inputs", 1),
    ("- name: Validate required production secrets", 1),
    ("- name: Verify update signing key pair", 1),
    ("- name: Build sign and notarize production package", 1),
    ("- name: Generate signed production update manifest", 1),
    ("- name: Publish production GitHub Release", 1),
    ("- name: Wait for published update endpoint", 1),
    ("- name: Verify published release and installed production app", 1),
    ("- name: Roll back failed published release", 1),
    ("- name: Upload production release bundle", 1),
    ("- name: Cleanup signing material", 1),
]:
    actual = production.count(marker)
    if actual != expected:
        errors.append(
            f"production release workflow must contain {marker!r} exactly "
            f"{expected} time(s), found {actual}"
        )

verify = (ROOT / ".github/workflows/verify-published-release.yml").read_text(
    encoding="utf-8"
)
for marker, expected in [
    ("- name: Validate verification inputs", 1),
    ("- name: Validate required verification secrets", 1),
    ("- name: Verify remote manifest and package before installation", 1),
    ("- name: Install exact package verified by release verifier", 1),
    ("- name: Produce full production release evidence", 1),
    ("- name: Launch verified production app", 1),
    ("- name: Upload production verification evidence", 1),
    ("- name: Cleanup notarization key", 1),
]:
    actual = verify.count(marker)
    if actual != expected:
        errors.append(
            f"published release verification must contain {marker!r} exactly "
            f"{expected} time(s), found {actual}"
        )
if "pull_request:" in verify or "push:" in verify:
    errors.append(
        "published release verification must remain explicit workflow_dispatch only"
    )
if "production-manifest.json" in verify:
    errors.append(
        "published release verification must not re-fetch an unbound manifest after cryptographic verification"
    )
if "curl " in verify or "\ncurl" in verify:
    errors.append(
        "published release verification must install the exact package emitted by BlackstockReleaseVerifier, not re-download it"
    )
if "--verified-package-output" not in verify:
    errors.append(
        "published release verification must persist the exact verifier-checked package for installation"
    )
if verify.count("--verified-manifest-output") != 1:
    errors.append(
        "published release verification must persist exactly one verified manifest snapshot before installation"
    )
if verify.count("--verified-package-output") != 1:
    errors.append(
        "published release verification must persist exactly one verified package snapshot before installation"
    )
if verify.count("--verified-manifest-input") != 1:
    errors.append(
        "post-install verification must consume the verified manifest snapshot exactly once"
    )
if verify.count("--verified-package-input") != 1:
    errors.append(
        "post-install verification must consume the verified package snapshot exactly once"
    )
if "post-install evidence diverged from pre-install verified snapshot" not in verify:
    errors.append(
        "published release workflow must cross-bind post-install evidence to pre-install evidence"
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
