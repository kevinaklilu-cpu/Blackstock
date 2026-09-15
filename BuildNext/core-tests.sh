#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${RUNNER_TEMP:-/tmp}/blackstock-next-core-tests"
xcrun swiftc -swift-version 5 \
  "$ROOT/BlackstockNext/Models.swift" \
  "$ROOT/BlackstockNext/YouTubeServices.swift" \
  "$ROOT/BlackstockNext/MomentEngine.swift" \
  "$ROOT/TestsNext/CoreTests.swift" \
  -o "$OUT"
"$OUT"
