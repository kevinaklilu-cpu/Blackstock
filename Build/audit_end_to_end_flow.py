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
        "AsyncImage(url: selected.thumbnailURL)",
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
        "resolveOriginalMedia(",
        "originalMediaLibraryPath",
    ],
    "Sources/BlackstockApp/WorkspaceProductViews.swift": [
        "discoveryPreview(item)",
        "session.useOpportunityAsClip(",
        "Video schneiden",
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
        "Videoquelle beziehen",
        "SourceDownloadManager()",
        "IngestDirectoryWatcher()",
        "PackagingReviewView(",
        "attemptAutomaticOriginalBinding()",
        "startIngestWatcher()",
        "acquireApprovedSource(",
        "session.resolveApprovedSourceMediaURL(",
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
    "Sources/BlackstockApp/SourceDownloadManager.swift": [
        "URLSessionDownloadDelegate",
        "byProducingResumeData:",
        "withResumeData:",
        "didWriteData",
        "didFinishDownloadingTo",
    ],
    "Sources/BlackstockApp/IngestDirectoryWatcher.swift": [
        "DispatchSource.makeFileSystemObjectSource",
        ".write",
        ".extend",
        "lastEventAt",
    ],
    "Sources/BlackstockCore/ApprovedSourceProviderClient.swift": [
        "ApprovedSourceProviderClient",
        "ApprovedSourceProviderRequest",
        "ApprovedSourceProviderResponse",
        "Authorization",
        "https",
    ],
    "Sources/BlackstockCore/LocalOriginalMediaMatcher.swift": [
        "LocalOriginalMediaMatcher",
        "supportedExtensions",
        "bestMatch(",
        "videoID:",
        "title:",
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
        "AsyncAVAssetExporter.export(",
        "Task.checkCancellation()",
    ],
    "Sources/BlackstockCore/AsyncAVAssetExporter.swift": [
        "withTaskCancellationHandler",
        "cancelExport()",
        "export(to: outputURL, as: fileType)",
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
