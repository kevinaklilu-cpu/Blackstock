#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

CONTRACTS = {
    "Sources/BlackstockCore/OAuthClientConfiguration.swift": [
        "parseGoogleDesktopJSON",
        "unsupportedClientType",
        "missingClientID",
        "invalidClientID",
        'hasSuffix(".apps.googleusercontent.com")',
        "clientSecret",
        'case clientSecret = "client_secret"',
        "projectID",
        "redirectURIs",
    ],
    "Sources/BlackstockCore/OAuthClientBindingPolicy.swift": [
        "requiresCredentialInvalidation",
        "normalize(previousClientID)",
        "normalize(nextClientID)",
    ],
    "Sources/BlackstockCore/GoogleOAuth.swift": [
        "SecRandomCopyBytes",
        '"code_challenge_method"',
        '"S256"',
        '.init(name: "state", value: state)',
        'access_type", value: "offline"',
        'prompt", value: "select_account consent"',
        '"code_verifier": verifier',
        '"client_secret"',
        "GoogleOAuthTokenEndpointError",
        "providerDescription",
        "oauthFormEncoded",
    ],
    "Sources/BlackstockCore/GoogleOAuthLifecycle.swift": [
        "Installed/desktop apps do not support Google's incremental authorization",
        "granted.union(required)",
        '"refresh_token"',
        '"client_secret"',
        "tokenEndpointError(",
    ],
    "Sources/BlackstockApp/LoopbackOAuthServer.swift": [
        'host: "127.0.0.1"',
        '"http://127.0.0.1:\\(port.rawValue)"',
        'fields[0] == "GET"',
        'url.path == "/"',
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "func importOAuthJSON",
        "OAuthClientBindingPolicy()",
        'withPrefix: "youtube."',
        'account: "google.oauth.importedClientID"',
        'account: "google.oauth.importedClientSecret"',
        "effectiveClientSecret",
        "clientSecret: effectiveClientSecret",
        "clearOAuthRuntimeAuthorizationState",
        "func removeImportedOAuthConfiguration",
        "validateStoredOAuthClient",
        'account: "youtube.\\(id).oauthClientID"',
    ],
    "Sources/BlackstockApp/FirstRunView.swift": [
        "Desktop-OAuth-JSON importieren …",
        "session.importOAuthJSON(from: url)",
        "session.connectGoogle()",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "Desktop-OAuth-JSON importieren …",
        "Desktop-OAuth-JSON ersetzen …",
        "Importierte OAuth-Konfiguration entfernen",
        "showOAuthImporter",
        "allowedContentTypes: [.json]",
        "session.importOAuthJSON(from: url)",
        "session.removeImportedOAuthConfiguration()",
    ],
    "Sources/BlackstockApp/BlackstockKeychain.swift": [
        "kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
        'private static let service = "de.blackstock.app"',
    ],
    "docs/THREAT_MODEL.md": [
        "Root-Pfad `/`",
        "http://127.0.0.1:<dynamischer Port>",
        "ausschließlich im macOS-Keychain",
    ],
}

TEST_CONTRACTS = {
    "Tests/BlackstockCoreTests/GoogleOAuthAndYouTubeTests.swift": [
        "testPKCEUsesS256AndURLSafeValues",
        "testAuthorizationRequestContainsDesktopPKCEAndLeastPrivilegeScope",
        "testOAuthJSONRequiresDesktopInstalledClient",
        "testOAuthJSONRejectsMissingAndInvalidClientIDs",
        "testOAuthJSONParsesDesktopClientSecretForTokenExchange",
        "testOAuthFormEncodingKeepsPKCEAndRedirectValuesValid",
        '"http://127.0.0.1:54321"',
    ],
    "Tests/BlackstockCoreTests/GoogleOAuthLifecycleTests.swift": [
        "testReadOnlyFirstRunNeedsOnlyReadScope",
        "testUploadReauthorizationRequestsUnionForInstalledApp",
        "testAlreadyAuthorizedCapabilityDoesNotRequestMoreScopes",
    ],
    "Tests/BlackstockCoreTests/OAuthClientBindingPolicyTests.swift": [
        "testSameNormalizedClientPreservesCredentials",
        "testChangedClientInvalidatesCredentials",
        "testAddingFirstConfiguredClientInvalidatesLegacyCredentials",
        "testRemovingOnlyConfiguredClientInvalidatesCredentials",
    ],
}

errors = []

for relative, markers in {**CONTRACTS, **TEST_CONTRACTS}.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing OAuth contract file: {relative}")
        continue
    source = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in source:
            errors.append(
                f"{relative}: missing OAuth contract marker: {marker}"
            )

session = (
    ROOT / "Sources/BlackstockApp/BlackstockSession.swift"
).read_text(encoding="utf-8")
import_start = session.find("func importOAuthJSON")
import_end = session.find(
    "@discardableResult\n    func removeLocalGoogleCredentials",
    import_start,
)
if import_start < 0 or import_end < 0:
    errors.append("Could not isolate importOAuthJSON implementation")
else:
    import_block = session[import_start:import_end]
    delete_index = import_block.find('withPrefix: "youtube."')
    client_id_index = import_block.find(
        'account: "google.oauth.importedClientID"'
    )
    secret_index = import_block.find(
        'account: "google.oauth.importedClientSecret"'
    )
    if (
        delete_index < 0
        or client_id_index < 0
        or secret_index < 0
        or delete_index > client_id_index
        or delete_index > secret_index
    ):
        errors.append(
            "Client-change token invalidation must occur before imported "
            "OAuth credentials become active"
        )

loopback = (
    ROOT / "Sources/BlackstockApp/LoopbackOAuthServer.swift"
).read_text(encoding="utf-8")
if "/oauth2/callback" in loopback:
    errors.append(
        "Desktop loopback redirect must remain the documented root URI"
    )

if errors:
    print("OAuth contract audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "OAuth audit passed: desktop JSON credentials, Keychain binding, "
    "PKCE/state, root loopback redirect, token-endpoint diagnostics and "
    "capability-based reauthorization remain connected."
)
