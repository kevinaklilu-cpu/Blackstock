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
python3 "$ROOT/Patches/Release1000/apply-clean-workflow-hotfix.py"

chmod +x "$ROOT"/Build/*.sh "$ROOT"/Build/*.zsh
grep -q '^APP_VERSION=1000.0.0$' "$ROOT/Build/version.env"
grep -q '^BUILD_NUMBER=100000$' "$ROOT/Build/version.env"
grep -q 'Blackstock 1000.0.0 (Build 100000)' "$ROOT/RELEASE_MANIFEST.txt"
grep -q 'CreatorOS1000View' "$ROOT/Sources/Blackstock/Views/RootView.swift"
grep -q 'v1000ProduktionMitQuelleStarten' "$ROOT/Sources/Blackstock/AppStore+V1000.swift"
grep -q 'case .command: "Dashboard"' "$ROOT/Sources/Blackstock/Models/Models.swift"
grep -q 'Text("BLACKSTOCK")' "$ROOT/Sources/Blackstock/Views/SidebarView.swift"
grep -q 'Clip aus Datei' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift"
grep -q 'AbschnittTitel(titel: "Videoideen"' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift"
grep -q 'Auf YouTube remixen' "$ROOT/Sources/Blackstock/Views/ChancenView.swift"
grep -q 'Originalton · Originalsprache · keine KI-Stimme' "$ROOT/Sources/Blackstock/Views/ChancenView.swift"
grep -q 'Label("Filter", systemImage: "line.3.horizontal.decrease")' "$ROOT/Sources/Blackstock/Views/ChancenView.swift"
grep -q 'DisclosureGroup("Schnittdetails & Quellen")' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift"
grep -q 'voiceover: nil' "$ROOT/Sources/Blackstock/AppStore+V11.swift"
grep -q 'musik: nil' "$ROOT/Sources/Blackstock/AppStore+V11.swift"
! grep -q 'BLACKSTOCK 1000' "$ROOT/Sources/Blackstock/Views/SidebarView.swift"
! grep -q '"Creator OS"' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift"
! grep -q 'Top 3 automatisch erstellen' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift"
grep -q 'BLACKSTOCK_1000_CORE_TESTS_OK' "$ROOT/Tests/Release1000CoreTests.swift"
echo BLACKSTOCK_1000_FLOW_RECONSTRUCT_OK
