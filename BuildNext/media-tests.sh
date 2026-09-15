#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${RUNNER_TEMP:-/tmp}/blackstock-next-media-tests"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDKROOT" -target arm64-apple-macosx13.0 \
  "$ROOT/BlackstockNext/Models.swift" \
  "$ROOT/BlackstockNext/MediaServices.swift" \
  "$ROOT/TestsNext/MediaIntegrationTests.swift" \
  -framework AVFoundation -framework Speech -framework CoreGraphics -framework CoreMedia -framework CoreVideo \
  -o "$OUT"
"$OUT"
