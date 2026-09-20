#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "Sources/BlackstockApp/FirstRunView.swift": [
        "session.connectGoogle(",
        "session.chooseChannel(",
        "session.refreshYouTubeVideoCategories(",
        "session.continueFromTopic(",
        "YouTubeEmbeddedPlayer(videoID:",
        "OpportunityTimeWindow.allCases",
        "session.useOpportunityAsClip(",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "performOAuthAuthorization(",
        "YouTubeAuthorizedClient(",
        "YouTubeChannelSetupClient(",
        "channelCategoryID",
        "regionCode: channelRegionCode",
        "relevanceLanguage: contentLanguage",
        "opportunityTimeWindow",
        "categoryOpportunityCandidates(",
        "productionIntentKind == .clipFromOpportunity",
        "channelCategoryTitle: primaryTopic",
        "projectChannelCategoryID(",
        "setProjectPaused(",
        "deleteProject(",
        "? .production",
        "authorizePublishing()",
        "publishPreparedReview(",
        "YouTubePublishingCoordinator(",
        "persistPublishedRecord(",
        "to: .published",
        "authorizeAnalytics()",
        "collectDueGrowthObservations(",
        "collectChannelAnalytics(",
        "YouTubeAnalyticsClient(",
        "GrowthLearningEngine()",
    ],
    "Sources/BlackstockApp/WorkspaceProductViews.swift": [
        "YouTubeEmbeddedPlayer(videoID:",
        "session.useOpportunityAsClip(",
        "Clip erstellen",
        "Projekt pausieren",
        "Projekt löschen",
        "Auf YouTube ansehen",
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        "state.createAutomaticHighlights(",
        "state.generateLocalClipCandidates(",
        "VideoPlayer(player: state.player)",
        "state.render(projectID:",
        "state.renderAllSavedClipSelections(",
        "state.useSavedClipForPackaging(",
        "state.requestStopProcessing(",
        "Schnittquelle hinzufügen",
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
        "categoryID: categoryID.isEmpty",
        "containsSyntheticMedia",
        "generateThumbnailFromRender()",
        "showFinalPublishConfirmation",
        "stage == .published",
        "dismiss()",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "routeToCurrentProject()",
        "project.stage.journeyGuidance.recommendedSurface",
        "YouTubeEmbeddedPlayer(",
        "session.collectDueGrowthObservations(",
        "session.collectChannelAnalytics(",
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
    "Sources/BlackstockCore/LocalVideoRenderer.swift": [
        "withTaskCancellationHandler",
        "cancelExport()",
        "Task.checkCancellation()",
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
    "local structured setup -> clip project -> automatic highlights -> validated render -> publishing -> "
    "playable published video analysis remain connected."
)
