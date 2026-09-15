#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/BlackstockNext"
fail(){ echo "BLACKSTOCK_MARKET_READY_AUDIT_FAIL: $1" >&2; exit 1; }

grep -q 'OpportunityEngine' "$SRC/YouTubeServices.swift" || fail "Opportunity Engine fehlt"
grep -q 'ChannelDNAService' "$SRC/YouTubeServices.swift" || fail "Channel DNA fehlt"
grep -q 'timestampedCommentMoments' "$SRC/YouTubeServices.swift" || fail "YouTube Moment-Signale fehlen"
grep -q 'sourceRightsConfirmed' "$SRC/AppState.swift" || fail "Rechte-Gate fehlt"
grep -q 'SecretVault' "$SRC/AppState.swift" || fail "Keychain fehlt"
grep -q 'AVAssetExportPresetHighestQuality' "$SRC/MediaServices.swift" || fail "High-Quality Export fehlt"
grep -q 'shouldOptimizeForNetworkUse = false' "$SRC/MediaServices.swift" || fail "Qualitätsorientierter Export fehlt"
grep -q 'QualityGate' "$SRC/MediaServices.swift" || fail "Post-Export QA fehlt"
grep -q 'Blackstock lädt dieses Video nicht herunter' "$SRC/Views.swift" || fail "YouTube Source-only Hinweis fehlt"
grep -q 'keine synthetischen Ersatzvideos' "$SRC/Views.swift" || fail "Source-first Produktvertrag fehlt"
! grep -R -E 'youtube-dl|yt-dlp|URLSession.*download|downloadTask' "$SRC" >/dev/null || fail "Downloader-Pfad gefunden"
! grep -R -E 'uploadType=resumable|videos\.insert|automatisch hochladen' "$SRC" >/dev/null || fail "Upload-Automatik gefunden"
! grep -R -E 'KI-Stimme erzeugen|synthetic video|Text-to-Video' "$SRC" >/dev/null || fail "Synthetische Videoerzeugung gefunden"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
SOURCES=("$SRC/Models.swift" "$SRC/YouTubeServices.swift" "$SRC/MomentEngine.swift" "$SRC/MediaServices.swift" "$SRC/AppState.swift" "$SRC/Views.swift" "$SRC/BlackstockApp.swift")
xcrun swiftc -swift-version 5 -parse-as-library -typecheck -sdk "$SDKROOT" -target arm64-apple-macosx13.0 \
  "${SOURCES[@]}" \
  -framework SwiftUI -framework AppKit -framework AVFoundation -framework WebKit -framework Speech -framework Security -framework UniformTypeIdentifiers -framework CoreGraphics -framework CoreMedia
"$ROOT/BuildNext/core-tests.sh"
echo BLACKSTOCK_MARKET_READY_AUDIT_OK
