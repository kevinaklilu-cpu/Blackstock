#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-dist}"
VERSION="${BLACKSTOCK_VERSION:-0.1.0}"
BUILD_NUMBER="${BLACKSTOCK_BUILD:-1}"
BUNDLE_ID="de.blackstock.app"
OAUTH_CLIENT_ID="${BLACKSTOCK_GOOGLE_OAUTH_CLIENT_ID:-}"
OAUTH_CLIENT_SECRET="${BLACKSTOCK_GOOGLE_OAUTH_CLIENT_SECRET:-}"
PUBLIC_PUBLISHING_APPROVED="${BLACKSTOCK_YOUTUBE_PUBLIC_PUBLISHING_APPROVED:-0}"
APP_SIGN_IDENTITY="${BLACKSTOCK_CODESIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${BLACKSTOCK_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${BLACKSTOCK_NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEY_PATH="${BLACKSTOCK_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${BLACKSTOCK_NOTARY_KEY_ID:-}"
NOTARY_ISSUER="${BLACKSTOCK_NOTARY_ISSUER:-}"
NOTARY_EVIDENCE_PATH="${BLACKSTOCK_NOTARY_EVIDENCE_PATH:-}"
UPDATE_MANIFEST_URL="${BLACKSTOCK_UPDATE_MANIFEST_URL:-}"
UPDATE_PUBLIC_KEY="${BLACKSTOCK_UPDATE_PUBLIC_KEY_BASE64:-}"
UPDATE_INSTALLER_TEAM_ID="${BLACKSTOCK_UPDATE_INSTALLER_TEAM_ID:-}"
INCLUDE_E2E_SMOKE="${BLACKSTOCK_INCLUDE_E2E_SMOKE:-0}"
PRODUCTION_RELEASE="${BLACKSTOCK_PRODUCTION_RELEASE:-0}"
SOURCE_COMMIT_SHA="${BLACKSTOCK_SOURCE_COMMIT_SHA:-}"

if [[ "$PUBLIC_PUBLISHING_APPROVED" == "1" ]]; then
  PUBLIC_PUBLISHING_PLIST="<true/>"
else
  PUBLIC_PUBLISHING_PLIST="<false/>"
fi

if [[ "$PRODUCTION_RELEASE" == "1" ]]; then
  if [[ ! "$SOURCE_COMMIT_SHA" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "Production release requires BLACKSTOCK_SOURCE_COMMIT_SHA as a 40-character Git commit SHA." >&2
    exit 1
  fi
  if [[ "$INCLUDE_E2E_SMOKE" == "1" ]]; then
    echo "Production release must not include the CI-only E2E helper." >&2
    exit 1
  fi
  for name in \
    APP_SIGN_IDENTITY \
    INSTALLER_SIGN_IDENTITY \
    UPDATE_MANIFEST_URL \
    UPDATE_PUBLIC_KEY \
    UPDATE_INSTALLER_TEAM_ID
  do
    if [[ -z "${!name}" ]]; then
      echo "Production release requires $name." >&2
      exit 1
    fi
  done
  python3 Build/validate_production_package_config.py \
    --manifest-url "$UPDATE_MANIFEST_URL" \
    --public-key-base64 "$UPDATE_PUBLIC_KEY" \
    --installer-team-id "$UPDATE_INSTALLER_TEAM_ID"

  if [[ -z "$NOTARY_PROFILE" && ( -z "$NOTARY_KEY_PATH" || -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER" ) ]]; then
    echo "Production release requires notarization credentials." >&2
    exit 1
  fi
fi

rm -rf "$OUT"
mkdir -p "$OUT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ARM64_BUILD="$WORK/build-arm64"
X86_64_BUILD="$WORK/build-x86_64"

swift build -c release --arch arm64 --scratch-path "$ARM64_BUILD"
swift build -c release --arch x86_64 --scratch-path "$X86_64_BUILD"

ARM64_BIN_DIR="$(
  swift build -c release --arch arm64     --scratch-path "$ARM64_BUILD"     --show-bin-path
)"
X86_64_BIN_DIR="$(
  swift build -c release --arch x86_64     --scratch-path "$X86_64_BUILD"     --show-bin-path
)"

require_universal_binary() {
  local binary="$1"
  local archs
  archs="$(lipo -archs "$binary")"
  for required_arch in arm64 x86_64; do
    if [[ " $archs " != *" $required_arch "* ]]; then
      echo "Required architecture $required_arch missing from $binary: $archs" >&2
      exit 1
    fi
  done
}

APP="$WORK/Blackstock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift Build/generate_app_icon.swift "$APP/Contents/Resources/Blackstock.icns"
test -s "$APP/Contents/Resources/Blackstock.icns"
lipo -create   "$ARM64_BIN_DIR/Blackstock"   "$X86_64_BIN_DIR/Blackstock"   -output "$APP/Contents/MacOS/Blackstock"
chmod +x "$APP/Contents/MacOS/Blackstock"
require_universal_binary "$APP/Contents/MacOS/Blackstock"

if [[ "$INCLUDE_E2E_SMOKE" == "1" ]]; then
  mkdir -p "$APP/Contents/Helpers"
  lipo -create     "$ARM64_BIN_DIR/BlackstockE2ESmoke"     "$X86_64_BIN_DIR/BlackstockE2ESmoke"     -output "$APP/Contents/Helpers/BlackstockE2ESmoke"
  chmod +x "$APP/Contents/Helpers/BlackstockE2ESmoke"
  require_universal_binary "$APP/Contents/Helpers/BlackstockE2ESmoke"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Blackstock</string>
<key>CFBundleExecutable</key><string>Blackstock</string>
<key>CFBundleIconFile</key><string>Blackstock.icns</string>
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundleName</key><string>Blackstock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>BlackstockSourceCommitSHA</key><string>${SOURCE_COMMIT_SHA}</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>Blackstock verwendet die Kamera nur nach deiner Freigabe, um autorisierte Produktionsaufnahmen direkt in dein lokales Projekt aufzunehmen.</string>
<key>NSMicrophoneUsageDescription</key><string>Blackstock verwendet das Mikrofon nur nach deiner Freigabe, um autorisierte Produktionsaufnahmen direkt in dein lokales Projekt aufzunehmen.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Blackstock transkribiert autorisierte Produktionsmedien lokal auf diesem Mac, wenn On-Device-Spracherkennung verfügbar ist.</string>
<key>BlackstockGoogleOAuthClientID</key><string>${OAUTH_CLIENT_ID}</string>
<key>BlackstockGoogleOAuthClientSecret</key><string>${OAUTH_CLIENT_SECRET}</string>
<key>BlackstockYouTubePublicPublishingApproved</key>${PUBLIC_PUBLISHING_PLIST}
<key>BlackstockUpdateManifestURL</key><string>${UPDATE_MANIFEST_URL}</string>
<key>BlackstockUpdatePublicKeyBase64</key><string>${UPDATE_PUBLIC_KEY}</string>
<key>BlackstockUpdateInstallerTeamID</key><string>${UPDATE_INSTALLER_TEAM_ID}</string>
</dict></plist>
PLIST

/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" | grep -qx "Blackstock.icns"
test -s "$APP/Contents/Resources/Blackstock.icns"

if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  if [[ "$INCLUDE_E2E_SMOKE" == "1" ]]; then
    codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP/Contents/Helpers/BlackstockE2ESmoke"
  fi
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Build/Blackstock.entitlements" \
    --sign "$APP_SIGN_IDENTITY" "$APP"
else
  if [[ "$INCLUDE_E2E_SMOKE" == "1" ]]; then
    codesign --force --sign - "$APP/Contents/Helpers/BlackstockE2ESmoke"
  fi
  codesign --force --deep --options runtime \
    --entitlements "$ROOT/Build/Blackstock.entitlements" \
    --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
require_universal_binary "$APP/Contents/MacOS/Blackstock"
if [[ "$INCLUDE_E2E_SMOKE" == "1" ]]; then
  require_universal_binary "$APP/Contents/Helpers/BlackstockE2ESmoke"
fi

PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/Applications"
cp -R "$APP" "$PAYLOAD/Applications/Blackstock.app"

COMPONENT="$WORK/Blackstock-component.pkg"
pkgbuild --root "$PAYLOAD" --install-location / --identifier "$BUNDLE_ID" --version "$VERSION" "$COMPONENT"

if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  productbuild --sign "$INSTALLER_SIGN_IDENTITY" --package "$COMPONENT" "$OUT/Blackstock.pkg"
else
  productbuild --package "$COMPONENT" "$OUT/Blackstock.pkg"
fi

NOTARY_AUTH=()
if [[ -n "$NOTARY_PROFILE" ]]; then
  NOTARY_AUTH=(
    --keychain-profile "$NOTARY_PROFILE"
  )
elif [[ -n "$NOTARY_KEY_PATH" || -n "$NOTARY_KEY_ID" || -n "$NOTARY_ISSUER" ]]; then
  if [[ -z "$NOTARY_KEY_PATH" || -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER" ]]; then
    echo "API-key notarization requires BLACKSTOCK_NOTARY_KEY_PATH, BLACKSTOCK_NOTARY_KEY_ID and BLACKSTOCK_NOTARY_ISSUER together." >&2
    exit 1
  fi
  NOTARY_AUTH=(
    --key "$NOTARY_KEY_PATH"
    --key-id "$NOTARY_KEY_ID"
    --issuer "$NOTARY_ISSUER"
  )
fi

if (( ${#NOTARY_AUTH[@]} > 0 )); then
  if [[ -z "$APP_SIGN_IDENTITY" || -z "$INSTALLER_SIGN_IDENTITY" ]]; then
    echo "Notarization requires BLACKSTOCK_CODESIGN_IDENTITY and BLACKSTOCK_INSTALLER_IDENTITY." >&2
    exit 1
  fi

  if [[ -n "$NOTARY_EVIDENCE_PATH" ]]; then
    NOTARY_RESPONSE="$NOTARY_EVIDENCE_PATH"
    mkdir -p "$(dirname "$NOTARY_RESPONSE")"
  else
    NOTARY_RESPONSE="$WORK/notary-response.json"
  fi

  xcrun notarytool submit "$OUT/Blackstock.pkg" \
    "${NOTARY_AUTH[@]}" \
    --wait \
    --output-format json > "$NOTARY_RESPONSE"

  python3 - "$NOTARY_RESPONSE" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
status = str(data.get("status", ""))
submission_id = str(data.get("id", ""))
if status.casefold() != "accepted":
    raise SystemExit(
        f"Notarization status is not Accepted: {status or 'missing'}"
    )
if not submission_id:
    raise SystemExit("Notarization response has no submission id")
print(f"Notarization accepted: {submission_id}")
PY

  xcrun stapler staple "$OUT/Blackstock.pkg"
  xcrun stapler validate "$OUT/Blackstock.pkg"
  spctl --assess --type install --verbose=2 "$OUT/Blackstock.pkg"
fi

pkgutil --payload-files "$OUT/Blackstock.pkg" | grep -q 'Applications/Blackstock.app'
shasum -a 256 "$OUT/Blackstock.pkg" > "$OUT/Blackstock.pkg.sha256"

echo "Created $OUT/Blackstock.pkg"