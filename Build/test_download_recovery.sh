#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name BlackstockCore \
  Sources/BlackstockCore/AsyncAVAssetExporter.swift Sources/BlackstockCore/YouTubeDownloadRequest.swift Sources/BlackstockCore/YouTubeMediaAssembler.swift \
  -o "$TEST_ROOT/libBlackstockCore.dylib" -emit-module-path "$TEST_ROOT/BlackstockCore.swiftmodule"
swiftc -swift-version 5 -enable-actor-data-race-checks -parse-as-library \
  -I "$TEST_ROOT" -L "$TEST_ROOT" -lBlackstockCore -Xlinker -rpath -Xlinker "$TEST_ROOT" \
  Sources/BlackstockApp/SourceDownloadManager.swift Build/DownloadRecoverySmoke.swift -o "$TEST_ROOT/smoke"
"$TEST_ROOT/smoke" "$TEST_ROOT"
