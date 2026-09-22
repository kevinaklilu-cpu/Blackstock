#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Build/prepare_download_tools.py
OUT="$PWD/.build/download-smoke"
mkdir -p "$OUT"
swiftc -swift-version 5 -emit-library -emit-module -module-name BlackstockCore \
  Sources/BlackstockCore/YouTubeDownloadRequest.swift Sources/BlackstockCore/YouTubeMediaAssembler.swift \
  -o "$OUT/libBlackstockCore.dylib" -emit-module-path "$OUT/BlackstockCore.swiftmodule"
swiftc -swift-version 5 -parse-as-library -I "$OUT" -L "$OUT" -lBlackstockCore \
  -Xlinker -rpath -Xlinker "$OUT" Sources/BlackstockApp/SourceDownloadManager.swift \
  Build/YouTubeDownloadSmoke.swift -o "$OUT/smoke"
BLACKSTOCK_DOWNLOAD_TOOLS_DIR="$PWD/.build/download-tools" \
  "$OUT/smoke" "$OUT/big-buck-bunny-$(date +%s).mp4"
