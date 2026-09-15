#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_VERSION="2.0.0"
BUILD_NUMBER="200000"
MIN_MACOS="13.0"
OUT="${BLACKSTOCK_NEXT_OUTPUT:-$ROOT/dist-next/Blackstock.app}"
BUILD_DIR="${BLACKSTOCK_NEXT_BUILD_DIR:-${RUNNER_TEMP:-/tmp}/blackstock-market-ready-build}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
rm -rf "$OUT" "$BUILD_DIR"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$BUILD_DIR"
SOURCES=(
  "$ROOT/BlackstockNext/Models.swift"
  "$ROOT/BlackstockNext/YouTubeServices.swift"
  "$ROOT/BlackstockNext/MomentEngine.swift"
  "$ROOT/BlackstockNext/MediaServices.swift"
  "$ROOT/BlackstockNext/AppState.swift"
  "$ROOT/BlackstockNext/Views.swift"
  "$ROOT/BlackstockNext/BlackstockApp.swift"
)
FRAMEWORKS=(
  -framework SwiftUI
  -framework AppKit
  -framework AVFoundation
  -framework WebKit
  -framework Speech
  -framework Security
  -framework UniformTypeIdentifiers
  -framework CoreGraphics
  -framework CoreMedia
)
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -whole-module-optimization \
    -sdk "$SDKROOT" -target "${ARCH}-apple-macosx${MIN_MACOS}" \
    -module-name BlackstockMarketReady \
    "${SOURCES[@]}" "${FRAMEWORKS[@]}" \
    -o "$BUILD_DIR/Blackstock-$ARCH"
done
lipo -create "$BUILD_DIR/Blackstock-arm64" "$BUILD_DIR/Blackstock-x86_64" -output "$OUT/Contents/MacOS/Blackstock"
chmod +x "$OUT/Contents/MacOS/Blackstock"
cat > "$OUT/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>de</string>
<key>CFBundleExecutable</key><string>Blackstock</string>
<key>CFBundleIdentifier</key><string>de.blackstock.marketready</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>Blackstock</string>
<key>CFBundleDisplayName</key><string>Blackstock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
<key>LSApplicationCategoryType</key><string>public.app-category.video</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSpeechRecognitionUsageDescription</key><string>Blackstock analysiert ausschließlich lokal ausgewählte, erlaubte Videodateien, um starke Schnittmomente zu erkennen.</string>
<key>NSMicrophoneUsageDescription</key><string>Blackstock benötigt keinen Live-Mikrofonzugriff für den normalen Schnittworkflow.</string>
<key>NSHumanReadableCopyright</key><string>Blackstock</string>
</dict></plist>
EOF
plutil -lint "$OUT/Contents/Info.plist"
codesign --force --deep --sign - "$OUT"
echo "BLACKSTOCK_MARKET_READY_BUILD_OK $OUT"
