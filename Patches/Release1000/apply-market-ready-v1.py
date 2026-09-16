from pathlib import Path

ROOT = Path.cwd()
trends = ROOT / "Sources/Blackstock/Views/ChancenView.swift"
dashboard = ROOT / "Sources/Blackstock/Views/CreatorOS1000View.swift"
production = ROOT / "Sources/Blackstock/Views/ProduktionsDetailView.swift"
audit = ROOT / "Build/Release-Audit.sh"


def replace_all(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new))


def append_once(path: Path, marker: str, block: str) -> None:
    text = path.read_text()
    if marker not in text:
        path.write_text(text.rstrip() + "\n" + block + "\n")

# Blackstock 1.0 product language: native platform actions first, local source second.
replace_all(trends, "Clip aus eigener/lizenzierter Datei", "Mit eigener Datei schneiden")
replace_all(trends, "Remix aus eigener/lizenzierter Datei", "Mit eigener Datei remixen")
replace_all(trends, "Clip aus Videodatei", "Mit eigener Datei schneiden")
replace_all(trends, "Remix aus Videodatei", "Mit eigener Datei remixen")
replace_all(trends, "In Blackstock schneiden", "Mit eigener Datei schneiden")
replace_all(trends, "Welche Rechte hast du an der Quelldatei?", "Ist das deine Datei oder darfst du sie verwenden?")
replace_all(trends, "eigene oder lizenzierte Videodatei", "eigene oder anderweitig erlaubte Videodatei")
replace_all(trends, "eigene/lizenzierte Datei", "eigene Datei")
replace_all(trends, "lizenzierte Datei", "erlaubte Datei")
replace_all(trends, "Nutzungsrechte bestätigen", "Datei verwenden")
replace_all(trends, "Bestätigen & schneiden", "Datei verwenden & schneiden")
replace_all(trends, "Auf YouTube remixen", "Clip / Remix auf YouTube")
replace_all(trends, "YouTube ist geöffnet. Nutze dort Remix → Ausschneiden.", "YouTube ist geöffnet. Nutze dort Clip oder Remix; Blackstock behält den Trend als Referenz.")
replace_all(trends, "Nutze dort Remix → Ausschneiden.", "Nutze dort Clip oder Remix.")

# Keep the dashboard product-first and reduce visual/interaction overload.
replace_all(dashboard, "Trend ansehen", "Trend öffnen")
replace_all(dashboard, "Bestehende Videos intelligent schneiden – Originalquelle wählen, besten Moment finden, hochwertig exportieren.",
            "Trends verstehen, schnell entscheiden und direkt in den passenden Creator-Workflow wechseln.")
replace_all(dashboard, "Quellvideo finden, stärksten Moment analysieren und mit Originalmaterial lokal schneiden.",
            "Trend öffnen, analysieren und mit einem klaren nächsten Schritt weiterarbeiten.")
replace_all(dashboard, "Trend verstehen, stärksten Moment planen und Originalmaterial mit optionalen Studio-Layern produzieren.",
            "Trend verstehen, Format wählen und ohne Umwege in Produktion oder YouTube-Remix wechseln.")
replace_all(dashboard, "Creator Intelligence · integriert", "Live Creator Intelligence")

# Production language should feel like one product, not a rights form.
replace_all(production, "Schnittquelle", "Material")
replace_all(production, "Originalmaterial", "Material")
replace_all(production, "Welche Rechte hast du an der Quelldatei?", "Ist das deine Datei oder darfst du sie verwenden?")
replace_all(production, "lizenzierte", "erlaubte")
replace_all(production, "Lizenzierte", "Erlaubte")

# Add a release-level market UX contract. This intentionally does not weaken copyright guardrails;
# it only removes legalistic wording from the primary creator journey.
append_once(audit, "# BLACKSTOCK_1_MARKET_UX_AUDIT", r'''# BLACKSTOCK_1_MARKET_UX_AUDIT
grep -q 'Clip / Remix auf YouTube' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Creator-first YouTube action fehlt"
grep -q 'Mit eigener Datei schneiden' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Sekundaerer Datei-Workflow fehlt"
! grep -q 'Clip aus eigener/lizenzierter Datei' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Alte Lizenzdatei-Sprache ist noch sichtbar"
! grep -q 'Remix aus eigener/lizenzierter Datei' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Alte Remix-Lizenzsprache ist noch sichtbar"
grep -q 'Live Creator Intelligence' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Live Dashboard-Sprache fehlt"
''')

print("BLACKSTOCK_1_MARKET_UX_OK")
