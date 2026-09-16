#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${1:-dist}"
VERSION="${BLACKSTOCK_VERSION:-1.0.0}"
BUILD_NUMBER="${BLACKSTOCK_BUILD:-103}"
IDENTIFIER="de.blackstock.native"
# Desktop OAuth + PKCE: only a client ID is embedded. A client secret does not belong in a native app bundle.
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

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 210, yRadius: 210).fill()

NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 132, y: 307, width: 760, height: 410), xRadius: 108, yRadius: 108).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 240, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
("B" as NSString).draw(in: NSRect(x: 205, y: 350, width: 245, height: 300), withAttributes: attrs)

NSColor(calibratedWhite: 1, alpha: 0.32).setFill()
NSBezierPath(rect: NSRect(x: 500, y: 395, width: 6, height: 234)).fill()

let play = NSBezierPath()
play.move(to: NSPoint(x: 590, y: 402))
play.line(to: NSPoint(x: 590, y: 622))
play.line(to: NSPoint(x: 774, y: 512))
play.close()
NSColor.white.setFill()
play.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
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
pkgbuild --root "$PAYLOAD" --install-location / --identifier "$IDENTIFIER" --version "$VERSION" "$COMPONENT"
productbuild --package "$COMPONENT" "$OUT_DIR/Blackstock-Installer.pkg"

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

Für die Google-Verbindung wird eine OAuth Client-ID vom Typ „Desktopanwendung“ verwendet.
Ein Client Secret wird in Blackstock absichtlich nicht gespeichert oder benötigt.

Hinweis: Dieser Community-Build ist ad-hoc signiert. macOS kann deshalb beim ersten Start einen Sicherheitshinweis anzeigen.
TXT

hdiutil create -volname "Blackstock Installer" -srcfolder "$STAGE" -ov -format UDZO "$OUT_DIR/Blackstock-Installer.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT_DIR/Blackstock.zip"

shasum -a 256 "$OUT_DIR/Blackstock-Installer.pkg" > "$OUT_DIR/Blackstock-Installer.pkg.sha256"
shasum -a 256 "$OUT_DIR/Blackstock-Installer.dmg" > "$OUT_DIR/Blackstock-Installer.dmg.sha256"
shasum -a 256 "$OUT_DIR/Blackstock.zip" > "$OUT_DIR/Blackstock.zip.sha256"

pkgutil --check-signature "$OUT_DIR/Blackstock-Installer.pkg" || true
pkgutil --payload-files "$OUT_DIR/Blackstock-Installer.pkg" | grep -q 'Applications/Blackstock.app'

echo "Created:"
ls -lh "$OUT_DIR/Blackstock-Installer.pkg" "$OUT_DIR/Blackstock-Installer.dmg" "$OUT_DIR/Blackstock.zip"
