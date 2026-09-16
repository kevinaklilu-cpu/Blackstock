from pathlib import Path
import re

ROOT = Path.cwd()
path = ROOT / "Sources/Blackstock/Views/CreatorOS1000View.swift"
audit = ROOT / "Build/Release-Audit.sh"
text = path.read_text()

# Remove visible pseudo-precision from the dashboard. Internal ranking remains available
# to order results, but creators should see reasons and actions rather than arbitrary scores.
patterns = [
    r'^\s*Text\("Chance[^\n]*\n',
    r'^\s*Text\("Score[^\n]*\n',
    r'^\s*Text\("Opportunity Score[^\n]*\n',
]
for pattern in patterns:
    text = re.sub(pattern, '', text, flags=re.MULTILINE)

# Normalize user-facing terminology without touching Swift type names.
text = text.replace('Text("Chancen")', 'Text("Trends")')
text = text.replace('Text("Top Chancen")', 'Text("Aktuell relevant")')
text = text.replace('Text("Beste Chancen")', 'Text("Aktuell relevant")')
text = text.replace('Text("Chance")', 'Text("Trend")')
text = text.replace('"Chance öffnen"', '"Trend öffnen"')
text = text.replace('"Chance ansehen"', '"Trend öffnen"')

# Make the hero and lane copy action-oriented and plain-language.
text = text.replace('"Live Creator Intelligence"', '"Was jetzt relevant ist"')
text = text.replace('"Creator Intelligence · integriert"', '"Aktuelle Trends · dein Kanal"')
text = text.replace('"Missionen"', '"Nächste Schritte"')
text = text.replace('"Produktionen"', '"In Arbeit"')
text = text.replace('"Production Lane"', '"In Arbeit"')

path.write_text(text)

audit_text = audit.read_text()
marker = '# BLACKSTOCK_1_DASHBOARD_SIMPLIFICATION_AUDIT'
if marker not in audit_text:
    audit_text += r'''

# BLACKSTOCK_1_DASHBOARD_SIMPLIFICATION_AUDIT
! grep -q 'Text("Chance' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Pseudo-praezise Chance-Anzeige noch sichtbar"
! grep -q 'Text("Score' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Score-Karte noch sichtbar"
grep -q 'Was jetzt relevant ist' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Vereinfachter Dashboard-Hero fehlt"
grep -q 'Nächste Schritte' "$ROOT/Sources/Blackstock/Views/CreatorOS1000View.swift" || fail "Klarer Next-Step-Bereich fehlt"
'''
    audit.write_text(audit_text)

print('BLACKSTOCK_1_DASHBOARD_SIMPLIFIED_OK')
