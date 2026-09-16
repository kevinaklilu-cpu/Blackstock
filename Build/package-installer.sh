#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${1:-dist}"
VERSION="${BLACKSTOCK_VERSION:-1.0.0}"
BUILD_NUMBER="${BLACKSTOCK_BUILD:-101}"
IDENTIFIER="de.blackstock.native"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

BIN="$(swift build -c release --show-bin-path)/Blackstock"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/Blackstock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blackstock"
chmod +x "$APP/Contents/MacOS/Blackstock"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDisplayName</key><string>Blackstock</string>
  <key>CFBundleExecutable</key><string>Blackstock</string>
  <key>CFBundleIdentifier</key><string>${IDENTIFIER}</string>
  <key>CFBundleName</key><string>Blackstock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/Applications"
cp -R "$APP" "$PAYLOAD/Applications/Blackstock.app"

COMPONENT="$WORK/Blackstock-component.pkg"
pkgbuild \
  --root "$PAYLOAD" \
  --install-location / \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  "$COMPONENT"

productbuild \
  --package "$COMPONENT" \
  "$OUT_DIR/Blackstock-Installer.pkg"

STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp "$OUT_DIR/Blackstock-Installer.pkg" "$STAGE/Blackstock installieren.pkg"
cat > "$STAGE/Installation.txt" <<'TXT'
BLACKSTOCK INSTALLIEREN

1. Öffne „Blackstock installieren.pkg“.
2. Folge dem macOS-Installer.
3. Blackstock wird in /Applications installiert.
4. Starte Blackstock anschließend über Programme oder Spotlight.

Hinweis: Dieser Community-Build ist ad-hoc signiert. macOS kann deshalb beim ersten Start einen Sicherheitshinweis anzeigen.
TXT

hdiutil create \
  -volname "Blackstock Installer" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$OUT_DIR/Blackstock-Installer.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT_DIR/Blackstock.zip"

shasum -a 256 "$OUT_DIR/Blackstock-Installer.pkg" > "$OUT_DIR/Blackstock-Installer.pkg.sha256"
shasum -a 256 "$OUT_DIR/Blackstock-Installer.dmg" > "$OUT_DIR/Blackstock-Installer.dmg.sha256"
shasum -a 256 "$OUT_DIR/Blackstock.zip" > "$OUT_DIR/Blackstock.zip.sha256"

pkgutil --check-signature "$OUT_DIR/Blackstock-Installer.pkg" || true
pkgutil --payload-files "$OUT_DIR/Blackstock-Installer.pkg" | grep -q 'Applications/Blackstock.app'

echo "Created:"
ls -lh "$OUT_DIR/Blackstock-Installer.pkg" "$OUT_DIR/Blackstock-Installer.dmg" "$OUT_DIR/Blackstock.zip"
