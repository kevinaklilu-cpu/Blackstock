#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "Sources/BlackstockApp/FirstRunView.swift": [
        "session.connectGoogle(",
        "session.chooseChannel(",
        "YouTubeEmbeddedPlayer(videoID:",
        "session.useOpportunityAsClip(",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "performOAuthAuthorization(",
        "YouTubeAuthorizedClient(",
        "firstOpportunityCandidates(",
        "productionIntentKind == .clipFromOpportunity",
        "? .production",
        "authorizePublishing()",
        "publishPreparedReview(",
        "YouTubePublishingCoordinator(",
        "persistPublishedRecord(",
        "to: .published",
        "authorizeAnalytics()",
        "collectDueGrowthObservations(",
        "YouTubeAnalyticsClient(",
        "GrowthLearningEngine()",
    ],
    "Sources/BlackstockApp/WorkspaceProductViews.swift": [
        "YouTubeEmbeddedPlayer(videoID:",
        "session.useOpportunityAsClip(",
        "Clip erstellen",
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        "state.createAutomaticHighlights(",
        "state.generateLocalClipCandidates(",
        "VideoPlayer(player: state.player)",
        "state.render(projectID:",
        "state.renderAllSavedClipSelections(",
        "state.useSavedClipForPackaging(",
        "PackagingReviewView(",
    ],
    "Sources/BlackstockApp/StudioState.swift": [
        "createAutomaticHighlights(",
        "LocalHighlightCandidateRanker()",
        "reframeAspectRatio = .portrait9x16",
        "captionVisualStyle = .strong",
        "burnInCaptionsEnabled = true",
        "renderAllSavedClipSelections()",
        "useSavedClipForPackaging(",
        "LocalVideoRenderer().render(",
        "hasCurrentTechnicalValidation",
    ],
    "Sources/BlackstockApp/PackagingReviewView.swift": [
        "session.authorizePublishing(",
        "session.publishPreparedReview(",
        "showFinalPublishConfirmation",
        "stage == .published",
        "dismiss()",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "routeToCurrentProject()",
        "project.stage.journeyGuidance.recommendedSurface",
        "YouTubeEmbeddedPlayer(",
        "session.collectDueGrowthObservations(",
        "session.loadPublishedComments(",
    ],
    "Sources/BlackstockCore/YouTubePublishingCoordinator.swift": [
        "uploadClient.upload(",
        "packagingClient.setThumbnail(",
        "packagingClient.uploadCaption(",
    ],
    "Sources/BlackstockCore/YouTubeResumableUploader.swift": [
        "YouTubeResumableUploader",
        "remoteCommitted",
    ],
    "Sources/BlackstockCore/YouTubeAnalyticsClient.swift": [
        "averageViewDuration",
        "averageViewPercentage",
        "subscribersGained",
        "subscribersLost",
    ],
}

errors = []
for relative, markers in checks.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing end-to-end source: {relative}")
        continue
    compact = re.sub(r"\s+", "", path.read_text(encoding="utf-8"))
    for marker in markers:
        compact_marker = re.sub(r"\s+", "", marker)
        if compact_marker not in compact:
            errors.append(f"{relative}: missing end-to-end link: {marker}")

if errors:
    print("End-to-end flow audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "End-to-end flow audit passed: Google/channel -> playable YouTube video -> "
    "clip project -> automatic highlights -> validated render -> publishing -> "
    "playable published video analysis remain connected."
)
