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
        "Video-Kategorie",
        "YouTube-Zielgruppe",
        "Hauptziel in Blackstock",
        "Weiter",
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
session = (
    ROOT / "Sources/BlackstockApp/BlackstockSession.swift"
).read_text(encoding="utf-8")
setup_start = session.find("private func channelSetupAccessToken(")
setup_end = session.find(
    "private func loadYouTubeChannelSetupOptions(",
    setup_start,
)
if setup_start < 0 or setup_end < 0:
    errors.append("Could not isolate onboarding token helper")
else:
    setup_block = session[setup_start:setup_end]
    if "validatedReadOnlyAccessToken(" not in setup_block:
        errors.append(
            "Onboarding setup must reuse the existing read-only YouTube session"
        )
    if "channelManagement" in setup_block or "performOAuthAuthorization(" in setup_block:
        errors.append(
            "Onboarding setup must not trigger channel-management reauthorization"
        )

continue_start = session.find("func continueFromTopic() async")
continue_end = session.find(
    "func prepareChannelAndLoadOpportunities() async",
    continue_start,
)
if continue_start < 0 or continue_end < 0:
    errors.append("Could not isolate structured setup continuation")
else:
    continue_block = session[continue_start:continue_end]
    if "applyAndVerify(" in continue_block:
        errors.append(
            "First-run preferences must not mutate the YouTube channel"
        )
    if 'forKey: "blackstock.workspace.regionCode"' not in continue_block:
        errors.append(
            "First-run preferences must persist the local Blackstock profile"
        )

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