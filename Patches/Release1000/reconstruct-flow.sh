#!/bin/bash
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
TMP="${RUNNER_TEMP:-/tmp}/blackstock1000-flow"
mkdir -p "$TMP"
cd "$ROOT"

/usr/bin/ditto -x -k "$ROOT/blackstock-build-payload.zip" "$ROOT"
chmod +x "$ROOT"/Build/*.sh "$ROOT"/Build/*.zsh
if [[ -f "$ROOT/Patches/WachstumView.swift" ]]; then
  cp "$ROOT/Patches/WachstumView.swift" "$ROOT/Sources/Blackstock/Views/WachstumView.swift"
fi
sed -i '' 's|lipo -verify_arch arm64 x86_64 "$MACOS/Blackstock"|lipo "$MACOS/Blackstock" -verify_arch arm64 x86_64|' "$ROOT/Build/build-app.zsh"
sed -i '' 's|lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/Blackstock"|lipo "$APP/Contents/MacOS/Blackstock" -verify_arch arm64 x86_64|' "$ROOT/Build/create-dmg.zsh" "$ROOT/Build/verify-release.zsh"

python3 "$ROOT/Patches/apply-v12.py"
sed -i '' 's|featureAutorisiert(.live, verbindungID:|featureAutorisiert(.liveManagement, verbindungID:|g' "$ROOT/Sources/Blackstock/AppStore+V12.swift"
python3 "$ROOT/Patches/apply-v13.py"

cat "$ROOT"/Patches/V25/final.part* > "$TMP/v25.b64"
base64 -d < "$TMP/v25.b64" > "$TMP/v25.gz"
gunzip -c "$TMP/v25.gz" > "$TMP/v25.patch"
patch --batch -p1 < "$TMP/v25.patch"
find "$ROOT" \( -name '*.orig' -o -name '*.rej' \) -delete
cat > "$ROOT/RELEASE_MANIFEST.txt" <<'EOF25'
Blackstock 25.0.0 (Build 2500)
Bundle ID: de.blackstock.native
Minimum macOS: 13.0
Creator flow: Channel -> Topic -> YouTube Trends -> Preview -> Clip/Remix -> Quality -> Render -> Upload -> Learning
EOF25
sed -i '' 's/RELEASE_NOTES_v14\.md/RELEASE_NOTES_v25.md/g' "$ROOT/Build/Release-Audit.sh"

cat "$ROOT"/Patches/Release50/final.part* > "$TMP/v50.b64"
base64 -d < "$TMP/v50.b64" > "$TMP/v50.gz"
gunzip -c "$TMP/v50.gz" > "$TMP/v50.patch"
patch --batch -p1 < "$TMP/v50.patch"
find "$ROOT" \( -name '*.orig' -o -name '*.rej' \) -delete

cat "$ROOT"/Patches/Release100/auth.part* > "$TMP/v100.b64"
base64 -d < "$TMP/v100.b64" > "$TMP/v100.gz"
gunzip -c "$TMP/v100.gz" > "$TMP/v100.patch"
test "$(shasum -a 256 "$TMP/v100.patch" | awk '{print $1}')" = "757850e2a4c1ab8d945eba0fad06e33c5a82291dc4bac70a29173a110a2f481c"
patch --batch -p1 < "$TMP/v100.patch"
python3 "$ROOT/Patches/Release100/apply-audio-hotfix.py"
python3 "$ROOT/Patches/Release100/apply-product-hotfix.py"

base64 -d < "$ROOT/Patches/Release1000/final.patch.gz.b64" > "$TMP/v1000.gz"
gunzip -c "$TMP/v1000.gz" > "$TMP/v1000.patch"
patch --batch -p1 < "$TMP/v1000.patch"
find "$ROOT" \( -name '*.orig' -o -name '*.rej' \) -delete

python3 "$ROOT/Patches/Release1000/apply-flow-hotfix.py"
python3 "$ROOT/Patches/Release1000/apply-ui-language-hotfix.py"
python3 "$ROOT/Patches/Release1000/apply-native-remix-hotfix.py"
python3 "$ROOT/Patches/Release1000/apply-player-time-compile-fix.py"
python3 "$ROOT/Patches/Release1000/apply-clean-workflow-hotfix.py"
python3 "$ROOT/Patches/Release1000/apply-release-audit-hotfix.py"

# Rights-aware source architecture remains the safety baseline for local renders.
base64 -d < "$ROOT/Patches/Release1000/source-only-studio-hotfix.py.gz.b64" > "$TMP/source-only-studio.py.gz"
gunzip -c "$TMP/source-only-studio.py.gz" > "$TMP/source-only-studio.py"
BLACKSTOCK_ROOT="$ROOT" python3 "$TMP/source-only-studio.py"

# Current Swift compatibility and integrated product tools.
python3 "$ROOT/Patches/Release1000/apply-swift63-compile-hotfix.py"
python3 "$ROOT/Patches/Release1000/apply-next-generation.py"
python3 "$ROOT/Patches/Release1000/apply-next-audit-hotfix.py"
python3 "$ROOT/Patches/Release1000/apply-blackstock-1.py"
python3 "$ROOT/Patches/Release1000/apply-market-ready-v1.py"
python3 "$ROOT/Patches/Release1000/apply-dashboard-simplification.py"
python3 "$ROOT/Patches/Release1000/apply-market-product-redesign.py"
python3 "$ROOT/Patches/Release1000/apply-market-audit-normalization.py"

# Transparent source assembly for the latest discovery/research/ideas architecture.
cat "$ROOT/Patches/Release1000/creator-business-os.src00" \
    "$ROOT/Patches/Release1000/creator-business-os.src01" \
    "$ROOT/Patches/Release1000/creator-business-os.src02" \
    "$ROOT/Patches/Release1000/creator-business-os.src03" \
    "$ROOT/Patches/Release1000/creator-business-os.src04" \
    "$ROOT/Patches/Release1000/creator-business-os.src05" > "$TMP/creator-business-os.py"
test "$(shasum -a 256 "$TMP/creator-business-os.py" | awk '{print $1}')" = "e1a6c0f70471795944c1f13c824775c8b3c651e916b61b21a099c8cbb7c05d12"
BLACKSTOCK_ROOT="$ROOT" python3 "$TMP/creator-business-os.py"

# Final public identity and static market-readiness gates run last so later patches cannot
# reintroduce generation codenames or version suffixes into the product UI.
python3 "$ROOT/Patches/Release1000/apply-final-branding-readiness.py"
chmod +x "$ROOT"/Build/*.sh "$ROOT"/Build/*.zsh
"$ROOT/Build/Market-Readiness-Audit.sh"

# Canonical product contract.
grep -q '^APP_VERSION=1.0.0$' "$ROOT/Build/version.env"
grep -q '^BUILD_NUMBER=100$' "$ROOT/Build/version.env"
grep -q 'Blackstock 1.0.0 (Build 100)' "$ROOT/RELEASE_MANIFEST.txt"
grep -q '^Product: Blackstock$' "$ROOT/RELEASE_MANIFEST.txt"
grep -q 'Text("BLACKSTOCK")' "$ROOT/Sources/Blackstock/Views/SidebarView.swift"
grep -q 'case .command: "Start"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'case .chancen: "Entdecken"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'case .research: "Recherche"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'case .ideen: "Ideen"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'case .produktionen: "Studio"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'case .veroeffentlicht: "Veröffentlichen"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'ResearchWorkspaceView()' "$ROOT/Sources/Blackstock/Views/RootView.swift"
grep -q 'IdeasWorkspaceView()' "$ROOT/Sources/Blackstock/Views/RootView.swift"
grep -q 'Nischen-Radar' "$ROOT/Sources/Blackstock/Views/CreatorBusinessWorkspaceView.swift"
grep -q 'Content Briefs' "$ROOT/Sources/Blackstock/Views/CreatorBusinessWorkspaceView.swift"
grep -q '("short", "relevance", "unter 4 Min.")' "$ROOT/Sources/Blackstock/Services/YouTubeService.swift"
! grep -q 'relevanceLanguage", value: "en"' "$ROOT/Sources/Blackstock/Services/YouTubeService.swift"
! grep -q 'sourceDuration >= 240' "$ROOT/Sources/Blackstock/Services/YouTubeService.swift"
! grep -Rqs 'Blackstock 1\.0' "$ROOT/Sources/Blackstock" --include='*.swift'
! grep -Rqs 'Creator Studio' "$ROOT/Sources/Blackstock" --include='*.swift'
! grep -Rqs 'Creator Business OS' "$ROOT/Sources/Blackstock" --include='*.swift'

grep -q 'case youtubeNativeRemix' "$ROOT/Sources/Blackstock/Models/Blackstock1000Models.swift"
! grep -q 'case originalBuild' "$ROOT/Sources/Blackstock/Models/Blackstock1000Models.swift"
grep -q 'blackstockSyncChannelIdentity' "$ROOT/Sources/Blackstock/AppStore+Guidance.swift"
grep -q 'Clip / Remix auf YouTube' "$ROOT/Sources/Blackstock/Views/ChancenView.swift"
grep -q 'YouTube bleibt der Hauptweg' "$ROOT/Sources/Blackstock/Views/ChancenView.swift"
grep -q 'voiceover: voiceoverURL' "$ROOT/Sources/Blackstock/AppStore+V11.swift"
grep -q 'musik: musicURL' "$ROOT/Sources/Blackstock/AppStore+V11.swift"
grep -q 'titel: "Studio"' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift"
grep -q 'Source-aware 4K' "$ROOT/Sources/Blackstock/Services/RenderQualityProfileService.swift"
grep -q 'AVAssetExportPresetHighestQuality' "$ROOT/Sources/Blackstock/Services/MasterVideoService.swift"
grep -q 'case time(Double)' "$ROOT/Sources/Blackstock/Views/YouTubePlayerView.swift"
grep -q 'BLACKSTOCK_1000_CORE_TESTS_OK' "$ROOT/Tests/Release1000CoreTests.swift"
echo BLACKSTOCK_CANONICAL_OK
