from pathlib import Path

path = Path.cwd() / "Build/Release-Audit.sh"
text = path.read_text()
old = '''grep -q 'timeline.captions = true' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Caption-Default fehlt"'''
new = '''grep -q 'timeline.captions = produktionen\[pIndex\].captionsAktiv ?? true' "$ROOT/Sources/Blackstock/AppStore+V11.swift" || fail "Konfigurierbarer Caption-Default fehlt"'''
if new in text:
    print("BLACKSTOCK_NEXT_CAPTION_AUDIT_ALREADY_OK")
elif old in text:
    path.write_text(text.replace(old, new, 1))
    print("BLACKSTOCK_NEXT_CAPTION_AUDIT_OK")
else:
    raise SystemExit("Expected caption default audit guard not found")
