#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "Sources/BlackstockCore/GoogleOAuthRevoker.swift": [
        "https://oauth2.googleapis.com/revoke",
        'request.httpMethod = "POST"',
    ],
    "Sources/BlackstockCore/PrivacyDataExporter.swift": [
        "Blackstock-Privacy-Export-",
        "OAuth Refresh Tokens",
        "Keychain-Geheimnisse",
    ],
    "Sources/BlackstockCore/PrivacyRetentionPolicy.swift": [
        "untilExplicitDeletion",
        "untilRevokedOrDeleted",
        "sessionOnly",
        "hours24",
        "userControlled",
        "purgeExpiredUpdatePackages",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "revokeGoogleAuthorization",
        "exportLocalPrivacyData",
        "PrivacyRetentionEnforcer().purgeExpiredUpdatePackages",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "Google-Berechtigung widerrufen",
        "Lokale Blackstock-Daten exportieren",
        "PrivacyRetentionPolicy.canonical",
    ],
    "Tests/BlackstockCoreTests/PrivacyControlsTests.swift": [
        "testGoogleRevokeRequestUsesOfficialHTTPSPostEndpoint",
        "testPrivacyExportCopiesLocalDataAndNeverAddsKeychainSecrets",
        "testRetentionPurgesOnlyExpiredBlackstockPackages",
        "testCanonicalRetentionPolicyCoversAllPrivacyClasses",
    ],
}

errors = []
for relative, markers in REQUIRED.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing privacy file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing privacy contract: {marker}")

if errors:
    print("Privacy audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Privacy audit passed: revoke, export and retention contracts are present.")
