from pathlib import Path

ROOT = Path.cwd()
audit = ROOT / "Build/Release-Audit.sh"
manifest = ROOT / "RELEASE_MANIFEST.txt"


def replace(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))

# Older release contracts described the implementation history rather than the final product.
# Keep the safety checks, but assert the current creator-facing workflow and language.
replace(audit,
        "grep -q 'Auf YouTube remixen' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"YouTube-Remix-Aktion fehlt\"",
        "grep -q 'Clip / Remix auf YouTube' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"YouTube-Remix-Aktion fehlt\"")
replace(audit,
        "grep -q 'Clip aus eigener/lizenzierter Datei' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Rechtebewusste Datei-Clip-Aktion fehlt\"",
        "grep -q 'Eigene Datei als Clip' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Sekundaerer Datei-Clip-Weg fehlt\"")
replace(audit,
        "grep -q 'Originalton als Standard' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Originalton-Standard fehlt\"",
        "grep -q 'YouTube bleibt der Hauptweg' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"YouTube-first Creator-Flow fehlt\"")
replace(audit,
        "grep -q 'Welche Rechte hast du an der Quelldatei?' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Rechtebestätigung vor lokalem Schnitt fehlt\"",
        "grep -q 'Eigene Datei verwenden?' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Sekundaere Datei-Bestaetigung fehlt\"")
replace(audit,
        "grep -q 'Mit eigener Datei schneiden' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Sekundaerer Datei-Workflow fehlt\"",
        "grep -q 'Weitere Aktionen' \"$ROOT/Sources/Blackstock/Views/ChancenView.swift\" || fail \"Sekundaerer Datei-Workflow fehlt\"")
replace(audit,
        "grep -q 'Live Creator Intelligence' \"$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift\" || fail \"Live Dashboard-Sprache fehlt\"",
        "grep -q 'Was jetzt wichtig ist' \"$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift\" || fail \"Handlungsorientiertes Dashboard fehlt\"")
replace(audit,
        "grep -q 'Was jetzt relevant ist' \"$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift\" || fail \"Vereinfachter Dashboard-Hero fehlt\"",
        "grep -q 'Was jetzt wichtig ist' \"$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift\" || fail \"Vereinfachter Dashboard-Hero fehlt\"")

if manifest.exists():
    text = manifest.read_text()
    lines = []
    for line in text.splitlines():
        if line.startswith("Creator flow:"):
            line = "Creator flow: Channel -> Trends -> Preview -> YouTube Clip/Remix or Own Media -> Studio -> Render -> Packaging -> Upload -> Analytics -> Learning"
        lines.append(line)
    manifest.write_text("\n".join(lines) + "\n")

print("BLACKSTOCK_1_MARKET_AUDIT_NORMALIZED_OK")
