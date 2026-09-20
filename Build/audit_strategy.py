#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "Sources/BlackstockCore/ChannelStrategyDraft.swift": [
        "missingContentPromise",
        "missingAudienceHypothesis",
        "missingPillars",
        "contentPromise: promise",
        "audienceHypothesis: audience",
        "pillars: pillars",
        "adjacentTopics:",
        "excludedTopics:",
        "objectives: [objective]",
    ],
    "Tests/BlackstockCoreTests/ChannelStrategyDraftTests.swift": [
        "testCreatesCompleteVersionedStrategyFromExplicitDraft",
        "testMissingStrategicEvidenceHardStops",
        "testListParsingDropsEmptyValuesAndDuplicates",
    ],
    "Sources/BlackstockApp/FirstRunView.swift": [
        "Content-Versprechen",
        "Zielgruppe",
        "Themenfelder, durch Komma getrennt",
        "Angrenzende Themen",
        "Ausgeschlossene Themen",
        'Picker(\n                        "Ziel",',
        'DisclosureGroup("Weitere Optionen")',
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "ChannelStrategyDraft(",
        "strategyContentPromise",
        "strategyAudienceHypothesis",
        "strategyPillarsText",
        "strategyObjective",
        "nextStrategyVersion(for:",
    ],
}

errors=[]
for relative, markers in REQUIRED.items():
    path=ROOT/relative
    if not path.is_file():
        errors.append(f"missing strategy file: {relative}")
        continue
    text=path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing strategy contract: {marker}")

if errors:
    print("Strategy audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)
print("Strategy audit passed: explicit complete versioned strategy is required.")