#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

UI_FILES = [
    "Sources/BlackstockApp/BlackstockApp.swift",
    "Sources/BlackstockApp/FirstRunView.swift",
    "Sources/BlackstockApp/StudioView.swift",
    "Sources/BlackstockApp/PackagingReviewView.swift",
]

BANNED_PRODUCT_TERMS = [
    "Workspace", "First Run", "Publishing", "Published", "Learning",
    "Growth", "Read-only", "Top-Level", "Captions", "Thumbnail",
    "Reframe", "On-Device",
]

string_pattern = re.compile(r'"(?:\\.|[^"\\])*"')
errors = []

for relative in UI_FILES:
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing UI source: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for literal in string_pattern.findall(text):
        for term in BANNED_PRODUCT_TERMS:
            if term in literal:
                errors.append(f"{relative}: visible product string contains forbidden English term {term}: {literal}")

packaging = ROOT / "Sources/BlackstockApp/PackagingReviewView.swift"
if packaging.is_file():
    text = packaging.read_text(encoding="utf-8")
    for marker in ["defaultLanguage: session.contentLanguage", "defaultAudioLanguage: transcript?.localeIdentifier", "?? session.contentLanguage"]:
        if marker not in text:
            errors.append(f"PackagingReviewView.swift: missing content-language separation marker: {marker}")

strategy = ROOT / "Sources/BlackstockApp/BlackstockSession.swift"
if strategy.is_file():
    text = strategy.read_text(encoding="utf-8")
    for marker in ['@Published var contentLanguage = "de"', '"blackstock.workspace.contentLanguage"', "contentLanguage: contentLanguage"]:
        if marker not in text:
            errors.append(f"BlackstockSession.swift: missing persisted content-language marker: {marker}")

if errors:
    print("Language audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Language audit passed: German product language and separate content language are enforced.")