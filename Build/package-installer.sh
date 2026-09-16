#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${1:-dist}"
VERSION="${BLACKSTOCK_VERSION:-1.0.0}"
BUILD_NUMBER="${BLACKSTOCK_BUILD:-102}"
IDENTIFIER="de.blackstock.native"
OAUTH_CLIENT_ID="${BLACKSTOCK_GOOGLE_OAUTH_CLIENT_ID:-}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

BIN="$(swift build -c release --show-bin-path)/Blackstock"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP="$WORK/Blackstock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blackstock"
chmod +x "$APP/Contents/MacOS/Blackstock"

cat > "$WORK/make-icon.swift" <<'SWIFT'
import AppKit
import Foundation

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()
NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220).fill()
NSColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 132, y: 292, width: 760, height: 440), xRadius: 118, yRadius: 118).fill()
NSColor.white.setFill()
let play = NSBezierPath()
play.move(to: NSPoint(x: 444, y: 388))
play.line(to: NSPoint(x: 662, y: 512))
play.line(to: NSPoint(x: 444, y: 636))
play.close()
play.fill()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swift "$WORK/make-icon.swift" "$WORK/icon-1024.png"
ICONSET="$WORK/Blackstock.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$WORK/icon-1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$WORK/icon-1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$WORK/icon-1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$WORK/icon-1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$WORK/icon-1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$WORK/icon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$WORK/icon-1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$WORK/icon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$WORK/icon-1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$WORK/icon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Blackstock.icns"

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
  <key>CFBundleIconFile</key><string>Blackstock</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>BlackstockGoogleOAuthClientID</key><string>${OAUTH_CLIENT_ID}</string>
</dict></plist>
PLIST

/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist" | grep -qx 'Blackstock'
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist" | grep -qx 'Blackstock'
test -f "$APP/Contents/Resources/Blackstock.icns"

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
5. Beim ersten Start verbindest du deinen YouTube-Account und wählst deinen Kanal.

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
