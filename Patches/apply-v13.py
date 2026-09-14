from pathlib import Path
import base64, gzip
CREATOR_LOOP_B64 = """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"""
RELEASE_NOTES_B64 = """H4sIAA5cqGoC/21Uy24TMRTd5yuu1GUnIYiqQuyISlOpUoCmVIIN8szcmTHjsSM/CM2KFR/AumKVf2DTFfmTfgnHnqRNq24m8eve87IPaKJE0TpvipZevhqNR2P695cmQaoS4/F4MNjbkCuWud87MqITyXTF1kmjnQ5dx5ak89Sy1ORk0fhcWMx9sKYMrdei49FgcHBAU642t431WHtrc5beiVyJUA2GNOPANPfCeod5pk56WrDthGbtuaO7n39OYnm9WReNixXmRWOl93c/b4bTIEu0GO7zYtuy1p5E8KYTXrqiycjkEXcudRl0ndGELQOtrDFindG50EI5b4XnWnJGl5Z16bIdEdAlU0bw2HbtmLCZZltAjkorIn1dRiTvpGZqFXSgMxEWXvTHF9bQl+C80CXh6yGa0W2wVnLshdqT4D1kjTVODdToWTqhVyxrJghoe5wZfVooI8oMsj1BTAHl4U9EdQVpTKz2mFwS+NS0wSVLIACV0nLraRU6qrhREY6mU1aJz0wUDUpWRtWWYTGQTo2pFQ9ffDbhMuQ8fFCWltKWFNnMgl/h5760fQpjGd229TYYsdOlWSA+0fDZM15Tv5G+McpDklR0cwvDY/FdHQDf3OQxobC3z9559AJuzBcWVBiN5rukuvsw57CwlCAggsN6yVjet991kCOFJUmcnF0a21bKLAlBrdjqRGLXreQQLeQdA37TC0Dfe7FQ6O7Xb7psuBNQ3XnF9W6ut7J62JWsJJHCl/KSZpES5JuWm3X0LE2hmWa5O/YxCCX9Zo0LBaWq7exFilv//8wUjRL3bQCNncNiZNKfvh5OYdgwsX5WDlw3tVlHTDHQln1GS2ERpUcvCb4A7lOZpcCVARnkahXIBx3fkN6rC1YsXPRoa8z2lcr23qiIrRPF+zlGh7gLWkJSB2UnUgt7TcJ2x0d0SD9eH389PhoN/gPPFK1i9QQAAA="""

def embedded(value: str) -> str:
    return gzip.decompress(base64.b64decode(value)).decode("utf-8")

root = Path.cwd()

def replace(path: Path, old: str, new: str, required: bool = True):
    text = path.read_text()
    if old not in text:
        if required:
            raise SystemExit(f"BLACKSTOCK_V13_PATCH_ERROR missing pattern in {path}: {old[:80]}")
        return
    path.write_text(text.replace(old, new))

# Main guided Blackstock dashboard.
(root / "Sources/Blackstock/Views/CreatorLoopView.swift").write_text(embedded(CREATOR_LOOP_B64))

# Product branding: the product is always Blackstock; version is release metadata only.
replace(root / "Sources/Blackstock/Views/SidebarView.swift", 'Text("BLACKSTOCK 12")', 'Text("BLACKSTOCK")')
replace(root / "Sources/Blackstock/Views/TopBarView.swift", 'store.ausgewaehltesZiel = .factory', 'store.ausgewaehltesZiel = .command')
replace(root / "Sources/Blackstock/Views/TopBarView.swift", 'Label("Erstellen", systemImage: "plus")', 'Label("Nächster Schritt", systemImage: "arrow.right.circle.fill")')

# Clear German workflow stage labels.
models = root / "Sources/Blackstock/Models/V12Models.swift"
for old, new in {
    'case strategy = "Channel DNA"': 'case strategy = "Thema festlegen"',
    'case trend = "Trend Intelligence"': 'case trend = "Trends finden"',
    'case source = "Source Analysis"': 'case source = "Video analysieren"',
    'case format = "Format Decision"': 'case format = "Format wählen"',
    'case remix = "Remix Director"': 'case remix = "Schneiden"',
    'case quality = "Quality Gate"': 'case quality = "Qualität prüfen"',
    'case render = "Render"': 'case render = "Rendern"',
    'case publish = "Upload"': 'case publish = "Hochladen"',
    'case learn = "Performance Learning"': 'case learn = "Verbessern"',
    '// MARK: - Blackstock 12 Creator Operating System': '// MARK: - Blackstock creator operating system',
}.items():
    replace(models, old, new)

# Remove visible old-version language from runtime messages.
for rel in ["Sources/Blackstock/AppStore+V12.swift", "Sources/Blackstock/AppStore+V11.swift"]:
    p = root / rel
    text = p.read_text()
    text = text.replace('// MARK: - Blackstock 12 Creator Intelligence', '// MARK: - Blackstock creator intelligence')
    text = text.replace('Creator Loop bereit: Lesen, Analytics und Upload sind verbunden.', 'Blackstock ist bereit: Kanal, Analytics und Upload sind verbunden.')
    text = text.replace('V12 Creator Loop · Source Analysis / Remix', 'Video analysieren und Remix vorbereiten')
    text = text.replace('V12 Quality Gate verbessern', 'Qualität vor dem Upload verbessern')
    text = text.replace('V12 Quality Gate:', 'Qualitätsprüfung:')
    text = text.replace('Blackstock V12 hält den Upload zurück, bis das Quality Gate erfüllt ist.', 'Blackstock hält den Upload zurück, bis die Qualitätsprüfung erfüllt ist.')
    p.write_text(text)

# After a successful connection, explicitly lead the user to the next task.
konten = root / "Sources/Blackstock/Views/KontenView.swift"
text = konten.read_text()
needle = "        networkSummary\n        zugangsSection"
replacement = "        networkSummary\n        if !store.liveKanaele.isEmpty { connectedNextStep }\n        zugangsSection"
if needle not in text:
    raise SystemExit("BLACKSTOCK_V13_PATCH_ERROR KontenView insertion point missing")
text = text.replace(needle, replacement, 1)
marker = "  private var zugangsSection: some View {"
banner = '''  private var connectedNextStep: some View {\n    HStack(spacing: 14) {\n      Image(systemName: "checkmark.circle.fill")\n        .font(.system(size: 22, weight: .semibold))\n        .foregroundStyle(Color.bsGreen)\n      VStack(alignment: .leading, spacing: 3) {\n        Text("Verbindung steht – so geht es weiter")\n          .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.bsText)\n        Text("Als Nächstes legst du Thema, Zielgruppe und Positionierung fest. Danach sucht Blackstock automatisch passende Trends für diesen Kanal.")\n          .font(.system(size: 10)).foregroundStyle(Color.bsMuted).lineSpacing(2)\n      }\n      Spacer()\n      Button("Weiter zur Übersicht") {\n        store.ausgewaehltesZiel = .command\n      }\n      .buttonStyle(.borderedProminent).tint(Color.bsRed).foregroundStyle(.white)\n    }\n    .blackstockCard(15, elevated: true)\n  }\n\n'''
if marker not in text:
    raise SystemExit("BLACKSTOCK_V13_PATCH_ERROR KontenView section marker missing")
text = text.replace(marker, banner + marker, 1)
konten.write_text(text)

# Release metadata.
(root / "Build/version.env").write_text("APP_VERSION=13.0.0\nBUILD_NUMBER=1300\nMIN_MACOS=13.0\nBUNDLE_ID=de.blackstock.native\n")
replace(root / "Sources/Blackstock/ReleaseInfo.swift", '"12.0.0"', '"13.0.0"')
replace(root / "Sources/Blackstock/ReleaseInfo.swift", '"1200"', '"1300"')

audit = root / "Build/Release-Audit.sh"
replace(audit, '[[ "$APP_VERSION" == "12.0.0" ]]', '[[ "$APP_VERSION" == "13.0.0" ]]')
replace(audit, '[[ "$BUILD_NUMBER" == "1200" ]]', '[[ "$BUILD_NUMBER" == "1300" ]]')
replace(audit, '[[ -f "$ROOT/RELEASE_NOTES_v12.md" ]] || fail "RELEASE_NOTES_v12.md fehlt"', '[[ -f "$ROOT/RELEASE_NOTES_v13.md" ]] || fail "RELEASE_NOTES_v13.md fehlt"')
# Runtime branding regression guard.
audit_text = audit.read_text()
guard = '''\nif grep -RInE 'BLACKSTOCK 12|Blackstock 12|Creator Loop · V12|V12 Quality Gate|V12-Produktion' \\\n  "$ROOT/Sources/Blackstock/Views" "$ROOT/Sources/Blackstock/AppStore+V11.swift" "$ROOT/Sources/Blackstock/AppStore+V12.swift" \\\n  >/tmp/blackstock-visible-version-branding.txt 2>/dev/null; then\n  cat /tmp/blackstock-visible-version-branding.txt >&2\n  fail "sichtbares altes Versionsbranding gefunden"\nfi\n'''
insert_at = 'SWIFTC_BIN="${SWIFTC:-swiftc}"\n'
if insert_at not in audit_text:
    raise SystemExit("BLACKSTOCK_V13_PATCH_ERROR Release-Audit insertion point missing")
audit.write_text(audit_text.replace(insert_at, guard + insert_at, 1))

(root / "RELEASE_NOTES_v13.md").write_text(embedded(RELEASE_NOTES_B64))
(root / "RELEASE_MANIFEST.txt").write_text(
    "Blackstock 13.0.0 (Build 1300)\n"
    "Bundle ID: de.blackstock.native\n"
    "Minimum macOS: 13.0\n"
    "Guided flow: Channel -> Strategy -> Trends -> Video -> Quality -> Render -> Upload -> Learning\n")

# Keep install/status docs current without turning the version number into product branding.
for name in ["INSTALLATION_EINFACH.md", "CI_STATUS.md", "ARCHITEKTUR.md", "PRODUCTION_CHECKLIST.md"]:
    p = root / name
    if not p.exists():
        continue
    t = p.read_text().replace("12.0.0", "13.0.0").replace("Build 1200", "Build 1300").replace("Blackstock 12", "Blackstock")
    p.write_text(t)

print("BLACKSTOCK_V13_PATCH_APPLIED")
