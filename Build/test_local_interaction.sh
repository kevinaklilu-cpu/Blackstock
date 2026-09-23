#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
swiftc -swift-version 5 -enable-actor-data-race-checks -parse-as-library \
  Sources/BlackstockApp/BlackstockKeychain.swift \
  Sources/BlackstockApp/IngestDirectoryWatcher.swift \
  Build/LocalInteractionSmoke.swift -o "$TEST_ROOT/smoke"
"$TEST_ROOT/smoke" "$TEST_ROOT/ingest"
