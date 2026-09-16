from pathlib import Path

ROOT = Path.cwd()
trends = ROOT / "Sources/Blackstock/Views/ChancenView.swift"
dashboard = ROOT / "Sources/Blackstock/Views/CreatorOS1000View.swift"
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
# Deliberately touch only known user-facing strings. Never globally rename words in Swift source,
# because labels such as "Originalmaterial" can also be part of internal API identifiers.
replace_all(trends, "Clip aus eigener/lizenzierter Datei", "Mit eigener Datei schneiden")
replace_all(trends, "Remix aus eigener/lizenzierter Datei", "Mit eigener Datei remixen")
replace_all(trends, "Clip aus Videodatei", "Mit eigener Datei schneiden")
replace_all(trends, "Remix aus Videodatei", "Mit eigener Datei remixen")
replace_all(trends, "In Blackstock schneiden", "Mit eigener Datei schneiden")
replace_all(trends, "Welche Rechte hast du an der Quelldatei?", "Ist das deine Datei oder darfst du sie verwenden?")
replace_all(trends, "eigene oder lizenzierte Videodatei", "eigene oder anderweitig erlaubte Videodatei")
replace_all(trends, "eigene/lizenzierte Datei", "eigene Datei")
replace_all(trends, "Nutzungsrechte bestätigen", "Datei verwenden")
replace_all(trends, "Bestätigen & schneiden", "Datei verwenden & schneiden")
replace_all(trends, "Auf YouTube remixen", "Clip / Remix auf YouTube")
replace_all(trends, "YouTube ist geöffnet. Nutze dort Remix → Ausschneiden.", "YouTube ist geöffnet. Nutze dort Clip oder Remix; Blackstock behält den Trend als Referenz.")
replace_all(trends, "Nutze dort Remix → Ausschneiden.", "Nutze dort Clip oder Remix.")

# Dashboard copy: plain-language actions instead of product-internal jargon.
replace_all(dashboard, "Trend ansehen", "Trend öffnen")
replace_all(dashboard, "Bestehende Videos intelligent schneiden – Originalquelle wählen, besten Moment finden, hochwertig exportieren.",
            "Trends verstehen, schnell entscheiden und direkt in den passenden Creator-Workflow wechseln.")
replace_all(dashboard, "Quellvideo finden, stärksten Moment analysieren und mit Originalmaterial lokal schneiden.",
            "Trend öffnen, analysieren und mit einem klaren nächsten Schritt weiterarbeiten.")
replace_all(dashboard, "Trend verstehen, stärksten Moment planen und Originalmaterial mit optionalen Studio-Layern produzieren.",
            "Trend verstehen, Format wählen und ohne Umwege in Produktion oder YouTube-Remix wechseln.")
replace_all(dashboard, "Creator Intelligence · integriert", "Live Creator Intelligence")

# Release-level market UX contract. Copyright guardrails remain in the data/action layer;
# creator-facing wording must not turn the primary journey into a legal form.
append_once(audit, "# BLACKSTOCK_1_MARKET_UX_AUDIT", r'''# BLACKSTOCK_1_MARKET_UX_AUDIT
grep -q 'Clip / Remix auf YouTube' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Creator-first YouTube action fehlt"
grep -q 'Mit eigener Datei schneiden' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Sekundaerer Datei-Workflow fehlt"
! grep -q 'Clip aus eigener/lizenzierter Datei' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Alte Lizenzdatei-Sprache ist noch sichtbar"
! grep -q 'Remix aus eigener/lizenzierter Datei' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Alte Remix-Lizenzsprache ist noch sichtbar"
grep -q 'Live Creator Intelligence' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Live Dashboard-Sprache fehlt"
''')

print("BLACKSTOCK_1_MARKET_UX_OK")
