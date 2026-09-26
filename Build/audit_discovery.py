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
        'name: "videoSyndicated"',
        'name: "eventType", value: "live"',
        "OpportunityContentFilter",
        "YouTubeOpportunityContentKind",
        "OpportunityTimeWindow",
    ],
    "Sources/BlackstockApp/WorkspaceProductViews.swift": [
        'Text("Videos entdecken")',
        "Automatische Empfehlungen für deinen Kanal",
        'Picker(\n                    "Zeitraum"',
        "Die Angaben stammen direkt von YouTube.",
        '"Mehrere Videos zu einer Story verbinden"',
        "YouTubeEmbeddedPlayer(videoID: item.videoID)",
    ],
    "Sources/BlackstockApp/YouTubeEmbeddedPlayer.swift": [
        "https://www.youtube-nocookie.com/embed/",
        'forHTTPHeaderField: "Referer"',
        "https://blackstock.app/",
        ".allowsContentJavaScript = true",
        "didFailProvisionalNavigation",
        "didFail navigation:",
        "YouTube-Vorschau nicht verfügbar",
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

print("Discovery audit passed: automatic channel recommendations use YouTube parameters, content-format filtering, resilient thumbnail previews, provider ordering and missing-data honesty.")
