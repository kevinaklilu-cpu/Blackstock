from pathlib import Path

ROOT = Path.cwd()
SOURCE_ROOT = ROOT / "Sources/Blackstock"


def replace_in(path: Path, old: str, new: str) -> None:
    if not path.exists():
        return
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))


# The product name is exactly "Blackstock". Version numbers remain metadata only.
if SOURCE_ROOT.exists():
    for path in SOURCE_ROOT.rglob("*.swift"):
        replace_in(path, "Blackstock 1.0", "Blackstock")
        replace_in(path, '"Creator Studio"', '"Studio"')
        replace_in(path, "wie in einem Creator Studio", "zentral")
        replace_in(path, "Creator Business OS", "Blackstock")
        replace_in(path, "Blackstock Next", "Blackstock")

manifest = ROOT / "RELEASE_MANIFEST.txt"
if manifest.exists():
    lines = []
    for line in manifest.read_text().splitlines():
        if line.startswith("Product:"):
            line = "Product: Blackstock"
        elif line.startswith("Architecture:"):
            line = "Architecture: Intelligence + Trends + Studio + Publishing + Analytics"
        lines.append(line)
    manifest.write_text("\n".join(lines) + "\n")

# A static release-readiness gate that can run without production credentials.
readiness = ROOT / "Build/Market-Readiness-Audit.sh"
readiness.write_text(r'''#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "MARKET_READINESS_FAIL: $1" >&2; exit 1; }

[[ -f "$ROOT/Build/version.env" ]] || fail "version.env fehlt"
source "$ROOT/Build/version.env"
[[ "$APP_VERSION" = "1.0.0" ]] || fail "unerwartete Version: $APP_VERSION"
[[ "$BUILD_NUMBER" = "100" ]] || fail "unerwarteter Build: $BUILD_NUMBER"
grep -q '^Product: Blackstock$' "$ROOT/RELEASE_MANIFEST.txt" || fail "Produktname ist nicht exakt Blackstock"

# No public generation codenames or version suffixes in shipping Swift UI/source.
! grep -Rqs 'Blackstock 1\.0' "$ROOT/Sources/Blackstock" --include='*.swift' || fail "Blackstock 1.0 ist noch als Produktname sichtbar"
! grep -Rqs 'Blackstock Next' "$ROOT/Sources/Blackstock" --include='*.swift' || fail "alter Produkt-Codename sichtbar"
! grep -Rqs 'Creator Business OS' "$ROOT/Sources/Blackstock" --include='*.swift' || fail "Creator Business OS ist noch sichtbar"
! grep -Rqs 'Creator Studio' "$ROOT/Sources/Blackstock" --include='*.swift' || fail "Creator Studio ist noch sichtbar"

# Shipping code must not contain obvious unfinished crash/placeholder markers.
! grep -RniE 'TODO|FIXME|fatalError\(|preconditionFailure\(' "$ROOT/Sources/Blackstock" --include='*.swift' >/dev/null || fail "unfertige/crashende Marker im Shipping-Code"

# Canonical product workflow and discovery invariants.
grep -q 'case .command: "Start"' "$ROOT/Sources/Blackstock/Models/Models.swift" || fail "Start-Navigation fehlt"
grep -q 'case .chancen: "Entdecken"' "$ROOT/Sources/Blackstock/Models/Models.swift" || fail "Entdecken-Navigation fehlt"
grep -q 'case .research: "Recherche"' "$ROOT/Sources/Blackstock/Models/Models.swift" || fail "Recherche-Navigation fehlt"
grep -q 'case .ideen: "Ideen"' "$ROOT/Sources/Blackstock/Models/Models.swift" || fail "Ideen-Navigation fehlt"
grep -q 'case .produktionen: "Studio"' "$ROOT/Sources/Blackstock/Models/Models.swift" || fail "Studio-Navigation fehlt"
grep -q 'case .veroeffentlicht: "Veröffentlichen"' "$ROOT/Sources/Blackstock/Models/Models.swift" || fail "Publishing-Navigation fehlt"
grep -q '("short", "relevance", "unter 4 Min.")' "$ROOT/Sources/Blackstock/Services/YouTubeService.swift" || fail "Short/kurze Discovery fehlt"
! grep -q 'relevanceLanguage", value: "en"' "$ROOT/Sources/Blackstock/Services/YouTubeService.swift" || fail "Discovery ist noch auf Englisch festgelegt"
! grep -q 'sourceDuration >= 240' "$ROOT/Sources/Blackstock/Services/YouTubeService.swift" || fail "alte 4-Minuten-Sperre aktiv"

echo BLACKSTOCK_MARKET_READINESS_STATIC_OK
''')
readiness.chmod(0o755)

print("BLACKSTOCK_FINAL_BRANDING_READINESS_OK")
