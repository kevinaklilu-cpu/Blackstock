#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

CONTRACTS = {
    "Sources/BlackstockCore/GoogleOAuth.swift": [
        'code_challenge_method", value: "S256"',
        'SecRandomCopyBytes',
        '.init(name: "state", value: state)',
        'https://oauth2.googleapis.com/token',
        '"code_verifier": verifier',
    ],
    "Sources/BlackstockApp/LoopbackOAuthServer.swift": [
        'host: "127.0.0.1"',
        '"/oauth2/callback"',
        'fields[0] == "GET"',
    ],
    "Sources/BlackstockApp/BlackstockKeychain.swift": [
        'kSecAttrAccessibleWhenUnlockedThisDeviceOnly',
        'kSecClassGenericPassword',
        'private static let service = "de.blackstock.app"',
    ],
    "Sources/BlackstockCore/UpdateManifest.swift": [
        'packageURL.scheme?.lowercased() == "https"',
        'Curve25519.Signing.PublicKey',
        'publicKey.isValidSignature',
        'manifest.sha256.count == 64',
    ],
    "Sources/BlackstockCore/InstallerPackageSignatureValidator.swift": [
        '"Developer ID Installer"',
        'teamIDMismatch',
        'signatureCheckFailed',
    ],
}

TEST_CONTRACTS = {
    "Tests/BlackstockCoreTests/UpdateManifestTests.swift": [
        "testHTTPPackageURLIsRejectedEvenWithValidSignature",
        "testTamperedManifestSignatureIsRejected",
    ],
    "Tests/BlackstockCoreTests/InstallerPackageSignatureValidatorTests.swift": [
        "testRejectsWrongInstallerTeam",
        "testRejectsNonDeveloperIDInstallerSignature",
        "testRejectsFailedPkgutilCheck",
    ],
}

errors = []

for relative, markers in {**CONTRACTS, **TEST_CONTRACTS}.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing security-critical file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing security contract: {marker}")

threat = ROOT / "docs/THREAT_MODEL.md"
if not threat.is_file():
    errors.append("missing docs/THREAT_MODEL.md")
else:
    threat_text = threat.read_text(encoding="utf-8")
    for heading in [
        "## Vertrauensgrenzen",
        "## Angreiferannahmen",
        "## Sicherheitskontrollen",
        "## Security-Test-Suite",
        "## Residual Risks / externe Gates",
    ]:
        if heading not in threat_text:
            errors.append(f"docs/THREAT_MODEL.md: missing section {heading}")

if errors:
    print("Security audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Security audit passed: threat model and critical source/test contracts are present.")
