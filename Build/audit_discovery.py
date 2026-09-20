#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "YouTubeAuthorizedClient(accessToken: accessToken)",
        "firstOpportunityCandidates(",
        "query: primaryTopic",
        "order: .relevance",
        "reloadOpportunities(order:",
    ],
    "Sources/BlackstockApp/FirstRunView.swift": [
        'Text("Videos")',
        'Text("YouTube-Daten")',
        "Blackstock ersetzt fehlende Werte nicht durch Schätzungen.",
        "Datenabruf:",
        "offiziellen Search-Order-Parameter",
        "keinen eigenen Opportunity- oder Virality-Score",
    ],
    "Tests/BlackstockCoreTests/OpportunityTransparencyTests.swift": [
        "testMissingYouTubeSignalsStayMissingInsteadOfBeingEstimated",
        "testOpportunityOrderingUsesOfficialYouTubeOrderParameters",
        "testRawMetricsRemainRawValues",
    ],
    "Sources/BlackstockCore/OpportunityProjectFactory.swift": [
        "externalID: videoID",
        "discoveredAt: opportunity.retrievedAt",
        "targetChannelID: channel",
    ],
}

errors = []
for relative, markers in REQUIRED.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing discovery file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing discovery contract: {marker}")

if errors:
    print("Discovery audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Discovery audit passed: real YouTube signals, provider ordering and score-free transparency are enforced.")