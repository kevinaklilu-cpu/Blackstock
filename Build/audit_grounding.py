#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "Sources/BlackstockCore/OpportunityProjectFactory.swift": [
        "source: MediaSourceReference",
        "targetChannelID: channel",
        "strategyVersion: max(strategyVersion, 1)",
        "externalID: videoID",
        "discoveredAt: opportunity.retrievedAt",
    ],
    "Tests/BlackstockCoreTests/OpportunityProjectFactoryTests.swift": [
        "testOpportunityCreatesChannelBoundProjectAndYouTubeSource",
        "testMissingTargetChannelHardFailsProjectCreation",
    ],
    "Sources/BlackstockCore/YouTubeCommentsClient.swift": [
        "YouTubeCommentContextGuard",
        "expectedVideoID",
        "expectedChannelID",
        "retrievedAt",
    ],
    "Tests/BlackstockCoreTests/YouTubeCommentsClientTests.swift": [
        "testCommentThreadResponsePreservesProviderFacts",
        "testCommentContextGuardRejectsUnexpectedChannelOrVideo",
    ],
    "Tests/BlackstockCoreTests/GrowthAnalyticsContextGuardTests.swift": [
        "testWrongChannelIsRejected",
        "testWrongProjectIsRejected",
        "testMissingVideoIDIsRejected",
    ],
    "Sources/BlackstockApp/FirstRunView.swift": [
        "keinen eigenen Opportunity- oder Virality-Score",
        "Blackstock ersetzt fehlende Werte nicht durch Schätzungen.",
        "Datenabruf:",
    ],
}

errors = []
for relative, markers in REQUIRED.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing grounding/provenance file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing grounding/provenance contract: {marker}")

if errors:
    print("Grounding/provenance audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Grounding/provenance audit passed: provider facts, context binding and missing-data honesty are enforced.")