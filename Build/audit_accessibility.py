#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

CRITICAL = {
    "Sources/BlackstockApp/FirstRunView.swift": [
        'accessibilityLabel("Kanalthema")',
        'accessibilityLabel("Video-Sortierung")',
        'accessibilityLabel("YouTube-Vorschau:',
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        'accessibilityLabel("Video-Vorschau des aktuellen Schnitts")',
        'accessibilityLabel("Trim-Start")',
        'accessibilityLabel("Trim-Ende")',
        'accessibilityLabel("Fokus horizontal")',
        'accessibilityLabel("Fokus vertikal")',
        'accessibilityLabel("Beat nach oben verschieben")',
        'accessibilityLabel("Beat nach unten verschieben")',
        'accessibilityLabel("Beat löschen")',
    ],
    "Sources/BlackstockApp/PackagingReviewView.swift": [
        'accessibilityLabel("YouTube-Beschreibung")',
        'accessibilityLabel("Variante des Veröffentlichungspakets löschen")',
        'accessibilityLabel("\\(areaTitle(area)) geprüft")',
        'accessibilityLabel("Prüfnotiz: \\(areaTitle(area))")',
    ],
}

errors = []

for relative, markers in CRITICAL.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing critical UI source: {relative}")
        continue

    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing required semantic marker: {marker}")

    for index, line in enumerate(lines):
        if ".labelsHidden()" not in line:
            continue
        window = "\n".join(lines[index:index + 7])
        if ".accessibilityLabel(" not in window:
            errors.append(
                f"{relative}:{index + 1}: labelsHidden() without nearby accessibilityLabel"
            )

    # Icon-only SwiftUI buttons must declare an explicit semantic label.
    for match in re.finditer(
        r"}\s*label:\s*\{\s*Image\(systemName:[\s\S]{0,180}?\n\s*\}",
        text,
    ):
        after = text[match.end():match.end() + 260]
        if ".accessibilityLabel(" not in after:
            line = text.count("\n", 0, match.start()) + 1
            errors.append(
                f"{relative}:{line}: icon-only Button without accessibilityLabel"
            )


# Strict canonical accessibility contracts beyond labels.
SCALING_AND_PRESENTATION = [
    "Sources/BlackstockApp/FirstRunView.swift",
    "Sources/BlackstockApp/StudioView.swift",
    "Sources/BlackstockApp/PackagingReviewView.swift",
    "Sources/BlackstockApp/BlackstockApp.swift",
]

for relative in SCALING_AND_PRESENTATION:
    path = ROOT / relative
    if not path.is_file():
        continue
    text = path.read_text(encoding="utf-8")

    if ".font(.system(size:" in text:
        errors.append(f"{relative}: fixed point font size defeats text scaling")

    if "withAnimation(" in text or ".animation(" in text:
        errors.append(f"{relative}: custom animation requires Reduced Motion handling")

    if "Color(red:" in text or "Color(.sRGB" in text:
        errors.append(f"{relative}: hard-coded RGB color bypasses system contrast behavior")

app = ROOT / "Sources/BlackstockApp/BlackstockApp.swift"
if app.is_file():
    app_text = app.read_text(encoding="utf-8")
    for marker in [
        "@FocusState private var queryFocused: Bool",
        ".focused($queryFocused)",
        "queryFocused = true",
        '.keyboardShortcut("k", modifiers: .command)',
        ".onExitCommand",
    ]:
        if marker not in app_text:
            errors.append(f"BlackstockApp.swift: missing keyboard/focus contract: {marker}")

if errors:
    print("Accessibility audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Accessibility audit passed: critical controls have explicit semantic labels.")
