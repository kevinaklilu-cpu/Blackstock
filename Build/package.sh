#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-dist}"
VERSION="${BLACKSTOCK_VERSION:-0.1.0}"
BUILD_NUMBER="${BLACKSTOCK_BUILD:-1}"
BUNDLE_ID="de.blackstock.app"
OAUTH_CLIENT_ID="${BLACKSTOCK_GOOGLE_OAUTH_CLIENT_ID:-}"
PUBLIC_PUBLISHING_APPROVED="${BLACKSTOCK_YOUTUBE_PUBLIC_PUBLISHING_APPROVED:-0}"
APP_SIGN_IDENTITY="${BLACKSTOCK_CODESIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${BLACKSTOCK_INSTALLER_IDENTITY:-}"
NOTARY_PROFILE="${BLACKSTOCK_NOTARY_KEYCHAIN_PROFILE:-}"

if [[ "$PUBLIC_PUBLISHING_APPROVED" == "1" ]]; then
  PUBLIC_PUBLISHING_PLIST="<true/>"
else
  PUBLIC_PUBLISHING_PLIST="<false/>"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

BIN_DIR="$(swift build -c release --show-bin-path)"
swift build -c release

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/Blackstock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Blackstock" "$APP/Contents/MacOS/Blackstock"
chmod +x "$APP/Contents/MacOS/Blackstock"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Blackstock</string>
<key>CFBundleExecutable</key><string>Blackstock</string>
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundleName</key><string>Blackstock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSpeechRecognitionUsageDescription</key><string>Blackstock transkribiert autorisierte Produktionsmedien lokal auf diesem Mac, wenn On-Device-Spracherkennung verfügbar ist.</string>
<key>BlackstockGoogleOAuthClientID</key><string>${OAUTH_CLIENT_ID}</string>
<key>BlackstockYouTubePublicPublishingApproved</key>${PUBLIC_PUBLISHING_PLIST}
</dict></plist>
PLIST

if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

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

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$APP_SIGN_IDENTITY" || -z "$INSTALLER_SIGN_IDENTITY" ]]; then
    echo "Notarization requires BLACKSTOCK_CODESIGN_IDENTITY and BLACKSTOCK_INSTALLER_IDENTITY." >&2
    exit 1
  fi

  xcrun notarytool submit "$OUT/Blackstock.pkg" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$OUT/Blackstock.pkg"
  xcrun stapler validate "$OUT/Blackstock.pkg"
  spctl --assess --type install --verbose=2 "$OUT/Blackstock.pkg"
fi

pkgutil --payload-files "$OUT/Blackstock.pkg" | grep -q 'Applications/Blackstock.app'
shasum -a 256 "$OUT/Blackstock.pkg" > "$OUT/Blackstock.pkg.sha256"

echo "Created $OUT/Blackstock.pkg"