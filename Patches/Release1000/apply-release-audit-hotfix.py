from pathlib import Path

root = Path.cwd()
path = root / "Build/Release-Audit.sh"
text = path.read_text()

old = '''grep -q 'Creator OS produzieren' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "One-Click-Creator-OS fehlt"'''
new = '''grep -q 'Auf YouTube remixen' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "YouTube-Remix-Aktion fehlt"
grep -q 'Clip aus Videodatei' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Datei-Clip-Aktion fehlt"
grep -q 'Originalton · Originalsprache · keine KI-Stimme' "$ROOT/Sources/Blackstock/Views/ChancenView.swift" || fail "Originalton-Sicherheitsregel fehlt"
grep -q 'DisclosureGroup("Schnittdetails & Quellen")' "$ROOT/Sources/Blackstock/Views/ProduktionsDetailView.swift" || fail "Reduzierter Produktionsfluss fehlt"
grep -q 'voiceover: nil' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Voiceover muss im Source-Edit deaktiviert sein"
grep -q 'musik: nil' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Zusatzmusik muss im Source-Edit deaktiviert sein"'''

if new not in text:
    if old not in text:
        raise SystemExit("Outdated Blackstock 1000 audit marker not found")
    text = text.replace(old, new, 1)

path.write_text(text)
print("BLACKSTOCK_1000_RELEASE_AUDIT_HOTFIX_OK")
