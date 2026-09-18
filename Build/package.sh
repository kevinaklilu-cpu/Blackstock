#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-dist}"
VERSION="${BLACKSTOCK_VERSION:-0.1.0}"
BUILD_NUMBER="${BLACKSTOCK_BUILD:-1}"
BUNDLE_ID="de.blackstock.app"
OAUTH_CLIENT_ID="${BLACKSTOCK_GOOGLE_OAUTH_CLIENT_ID:-}"

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
<key>BlackstockGoogleOAuthClientID</key><string>${OAUTH_CLIENT_ID}</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/Applications"
cp -R "$APP" "$PAYLOAD/Applications/Blackstock.app"

COMPONENT="$WORK/Blackstock-component.pkg"
pkgbuild --root "$PAYLOAD" --install-location / --identifier "$BUNDLE_ID" --version "$VERSION" "$COMPONENT"
productbuild --package "$COMPONENT" "$OUT/Blackstock.pkg"

pkgutil --payload-files "$OUT/Blackstock.pkg" | grep -q 'Applications/Blackstock.app'
shasum -a 256 "$OUT/Blackstock.pkg" > "$OUT/Blackstock.pkg.sha256"

echo "Created $OUT/Blackstock.pkg"