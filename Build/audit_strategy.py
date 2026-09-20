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
        "Land / Region",
        "Content-Sprache",
        "Kanal-Kategorie",
        "YouTube-Zielgruppe",
        "Hauptziel in Blackstock",
        "YouTube-Einstellungen übernehmen",
        "Trend-Zeitraum",
        "refreshYouTubeVideoCategories",
    ],
    "Sources/BlackstockCore/YouTubeChannelSetupClient.swift": [
        "supportedLanguages",
        "supportedRegions",
        "videoCategories",
        "currentChannelSetup",
        "updateBranding",
        "applyAndVerify",
        "selfDeclaredMadeForKids",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "ChannelStrategyDraft(",
        "strategyContentPromise",
        "strategyAudienceHypothesis",
        "strategyPillarsText",
        "strategyObjective",
        "channelCategoryID",
        "channelRegionCode",
        "channelAudienceSetting",
        "opportunityTimeWindow",
        "YouTubeChannelSetupClient(",
        "applyAndVerify(",
        "nextStrategyVersion(",
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

first_run = (
    ROOT / "Sources/BlackstockApp/FirstRunView.swift"
).read_text(encoding="utf-8")
for forbidden in [
    'TextField("Thema',
    'Zielgruppe, z. B.',
    '"Content-Versprechen"',
    '"Inhaltliche Säulen',
    '"Angrenzende Themen',
    '"Ausgeschlossene Themen',
]:
    if forbidden in first_run:
        errors.append(
            "First Run must use structured YouTube parameters, "
            f"not strategic free text: {forbidden}"
        )

if errors:
    print("Strategy audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)
print("Strategy audit passed: structured YouTube-backed setup feeds a complete versioned strategy without onboarding free text.")