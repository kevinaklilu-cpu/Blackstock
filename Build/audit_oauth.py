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
        'code_challenge_method", value: "S256"',
        '.init(name: "state", value: state)',
        'access_type", value: "offline"',
        'prompt", value: "select_account consent"',
        '"code_verifier": verifier',
    ],
    "Sources/BlackstockCore/GoogleOAuthLifecycle.swift": [
        "Installed/desktop apps do not support Google's incremental authorization",
        "case channelManagement",
        "youtubeForceSSL",
        "granted.union(required)",
        "refresh_token",
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
        'deleteAccounts(',
        'withPrefix: "youtube."',
        'account: "google.oauth.importedClientID"',
        'account: "google.oauth.importedClientSecret"',
        "clientSecret: effectiveClientSecret",
        "clearOAuthRuntimeAuthorizationState",
        "func removeImportedOAuthConfiguration",
        "validateStoredOAuthClient",
        'account: "youtube.\\(id).oauthClientID"',
    ],
    "Sources/BlackstockApp/FirstRunView.swift": [
        "Eigene Desktop-OAuth-JSON auswählen …",
        "session.importOAuthJSON(from: url)",
        "Zugangsdaten werden im macOS-Keychain gespeichert.",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "Desktop-OAuth-JSON importieren …",
        "Desktop-OAuth-JSON ersetzen …",
        "Importierte OAuth-Konfiguration entfernen",
        "showOAuthImporter",
        "allowedContentTypes: [.json]",
        "session.importOAuthJSON(from: url)",
        "session.removeImportedOAuthConfiguration()",
        "showOAuthImporter",
    ],
    "Sources/BlackstockApp/BlackstockKeychain.swift": [
        "kSecAttrAccessibleWhenUnlockedThisDeviceOnly",
        'private static let service = "de.blackstock.app"',
    ],
    "docs/THREAT_MODEL.md": [
        "Root-Pfad `/`",
        "http://127.0.0.1:<dynamischer Port>",
        "persistiert ein optionales Desktop-`client_secret` ausschließlich im macOS-Keychain",
    ],
}

TEST_CONTRACTS = {
    "Tests/BlackstockCoreTests/GoogleOAuthAndYouTubeTests.swift": [
        "testPKCEUsesS256AndURLSafeValues",
        "testAuthorizationRequestContainsDesktopPKCEAndLeastPrivilegeScope",
        "testOAuthJSONRequiresDesktopInstalledClient",
        "testOAuthJSONRejectsMissingAndInvalidClientIDs",
        "testOAuthJSONParsesDesktopClientSecretForKeychainBackedExchange",
        '"http://127.0.0.1:54321"',
    ],
    "Tests/BlackstockCoreTests/GoogleOAuthLifecycleTests.swift": [
        "testDiscoveryReadOnlyNeedsOnlyReadScope",
        "testChannelManagementRequiresForceSSLScope",
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
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(
                f"{relative}: missing OAuth contract marker: {marker}"
            )

config = (
    ROOT / "Sources/BlackstockCore/OAuthClientConfiguration.swift"
).read_text(encoding="utf-8")
if "clientSecret" not in config or 'client_secret' not in config:
    errors.append(
        "OAuthClientConfiguration must parse the optional desktop client_secret"
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
    if 'account: "google.oauth.importedClientSecret"' not in import_block:
        errors.append(
            "OAuth JSON import must store the optional desktop client_secret in Keychain"
        )
    delete_index = import_block.find('withPrefix: "youtube."')
    write_index = import_block.find(
        'account: "google.oauth.importedClientID"'
    )
    if delete_index < 0 or write_index < 0 or delete_index > write_index:
        errors.append(
            "Client-change token invalidation must occur before the new "
            "imported OAuth client ID becomes active"
        )


def function_block(source, signature):
    start = source.find(signature)
    if start < 0:
        return None
    next_function = source.find("\n    func ", start + len(signature))
    if next_function < 0:
        return source[start:]
    return source[start:next_function]

for signature in [
    "func prepareChannelAndLoadOpportunities() async",
    "func reloadOpportunities(order: OpportunitySortMode) async",
    "func loadWorkspaceOpportunities(",
]:
    block = function_block(session, signature)
    if block is None:
        errors.append(
            f"Could not isolate OAuth-backed discovery function: {signature}"
        )
        continue
    if "validatedReadOnlyAccessToken(" not in block:
        errors.append(
            f"{signature} must use the centralized refresh-aware YouTube token path"
        )
    if "tokenSet?.accessToken" in block:
        errors.append(
            f"{signature} must not bypass token-expiry validation with the runtime token"
        )
    if ".accessToken\")" in block and "BlackstockKeychain.read(" in block:
        errors.append(
            f"{signature} must not read a raw cached YouTube access token directly"
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
    "OAuth audit passed: desktop JSON import, client-bound Keychain "
    "credentials, PKCE/state, root loopback redirect and one-time connected "
    "YouTube authorization remain connected."
)
