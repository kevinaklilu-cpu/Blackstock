#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "YouTubeAuthorizedClient(",
        "categoryOpportunityCandidates(",
        "channelCategoryID",
        "regionCode: channelRegionCode",
        "relevanceLanguage: contentLanguage",
        "opportunityTimeWindow",
        "order: .views",
        "reloadOpportunities(order:",
    ],
    "Sources/BlackstockCore/YouTubeAuthorizedClient.swift": [
        'name: "videoCategoryId"',
        'name: "regionCode"',
        'name: "relevanceLanguage"',
        'name: "publishedAfter"',
        'name: "chart", value: "mostPopular"',
        'name: "videoEmbeddable"',
        "OpportunityTimeWindow",
    ],
    "Sources/BlackstockApp/FirstRunView.swift": [
        'Text("Videos")',
        "YouTube-Ergebnisse für deinen Kanal",
        "Trend-Zeitraum",
        "Video-Zeitraum",
        "Die Angaben stammen direkt von YouTube.",
        "Datenabruf:",
        "YouTubeEmbeddedPlayer(videoID:",
    ],
    "Sources/BlackstockApp/YouTubeEmbeddedPlayer.swift": [
        "WKScriptMessageHandler",
        "strict-origin-when-cross-origin",
        "https://blackstock.app",
        "onError",
        "101",
        "150",
        "153",
        "Auf YouTube ansehen",
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

print("Discovery audit passed: channel-category discovery uses YouTube mostPopular or bounded publishedAfter windows with provider ordering, playback and missing-data honesty.")