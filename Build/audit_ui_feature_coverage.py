#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

requirements = {
    "Sources/BlackstockApp/FirstRunView.swift": [
        "session.importOAuthJSON(",
        "session.connectGoogle(",
        "session.chooseChannel(",
        "session.continueFromTopic(",
        "session.refreshYouTubeVideoCategories(",
        "OpportunityTimeWindow.allCases",
        "session.setWorkspaceRightsResponsibilityAccepted(",
        "session.prepareChannelAndLoadOpportunities(",
        "session.useOpportunityAsClip(",
    ],
    "Sources/BlackstockApp/WorkspaceProductViews.swift": [
        "session.loadWorkspaceOpportunities(",
        "OpportunityTimeWindow.allCases",
        "OpportunityContentFilter.allCases",
        "session.youtubeVideoCategories",
        "session.youtubeRegions",
        "session.youtubeLanguages",
        "session.useOpportunity(",
        "session.useOpportunityAsClip(",
        "session.setWorkspaceRightsResponsibilityAccepted(",
        "session.setProjectPaused(",
        "session.deleteProject(",
        "Auf YouTube ansehen",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "NavigationSplitView",
        "ResearchAnalysisJourneyView(",
        "session.completeResearch(",
        "session.completeAnalysis(",
        "session.collectDueGrowthObservations(",
        "session.collectChannelAnalytics(",
        "session.authorizeAnalytics(",
        "ChannelAnalyticsWorkspaceView(",
        'Text("Creator Dashboard")',
        "session.loadPublishedComments(",
        "session.exportLocalPrivacyData(",
        "session.revokeGoogleAuthorization(",
        "session.removeAllLocalBlackstockData(",
        "BlackstockUpdateChecker().check(",
        "BlackstockUpdatePackageDownloader()",
        "BlackstockUpdateInstallationPreflight()",
        "NSWorkspace.shared.open(",
        "BlackstockCaptureHardwareAudit.loadEvidence(",
        'GroupBox("Original-Mediathek")',
        "chooseOriginalMediaLibrary()",
        "session.setOriginalMediaLibrary(",
    ],
    "Sources/BlackstockApp/CaptureCapabilityPanel.swift": [
        "cameraRecorder.startRecording(",
        "cameraRecorder.stopRecording(",
        "microphoneRecorder.startRecording(",
        "microphoneRecorder.stopRecording(",
        "screenRecorder.startRecording(",
        "screenRecorder.stopRecording(",
        "onRecordedMedia(url,.camera)",
        "onRecordedMedia(url,.microphone)",
        "onRecordedMedia(url,.screen)",
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        "CaptureCapabilityPanel",
        "state.importMovie(",
        "state.importSupplementalCapture(",
        "state.generateLocalClipCandidates(",
        "state.createAutomaticHighlights(",
        "state.requestStopProcessing(",
        "state.previewLocalClipCandidate(",
        "state.saveLocalClipCandidate(",
        "state.applyLocalClipCandidate(",
        "state.applyTrim(",
        "state.applyRemoveRange(",
        "state.applyTextOverlay(",
        "state.prepareOutputPreset(",
        "state.suggestFocalPoint(",
        "state.applyReframe(",
        "state.applyMasterVolume(",
        "state.generateLocalCaptions(",
        "state.setBurnInCaptionsEnabled(",
        "state.setCaptionVisualStyle(",
        "state.updateCaptionSegment(",
        "state.analyzeRetentionLocally(",
        "state.addStoryboardBeat(",
        "state.updateStoryboardBeat(",
        "state.moveStoryboardBeat(",
        "state.removeStoryboardBeat(",
        "state.setSupplementalAudioEnabled(",
        "state.setSupplementalAudioVolume(",
        "state.setSupplementalVideoEnabled(",
        "state.setSupplementalVideoTimelineStart(",
        "state.setSupplementalVideoSourceStart(",
        "state.setSupplementalVideoDuration(",
        "state.render(projectID:",
        "state.renderAllSavedClipSelections(",
        "state.exportRenderedSavedClips(",
        "state.useSavedClipForPackaging(",
        "attemptAutomaticOriginalBinding()",
        "session.resolveOriginalMedia(",
        "SourceDownloadManager()",
        "IngestDirectoryWatcher()",
        "startIngestWatcher()",
    ],
    "Sources/BlackstockApp/PackagingReviewView.swift": [
        'GroupBox("YouTube-Metadaten")',
        'GroupBox("Kapitel")',
        'GroupBox("Vorschaubild&Untertitel")',
        'GroupBox("VariantendesVeröffentlichungspakets")',
        'GroupBox("QualitativePrüfung")',
        "LocalThumbnailFrameGenerator()",
        "ThumbnailTechnicalInspector()",
        "session.importPackagingAsset(",
        "session.savePublishPreparation(",
        "session.ensureYouTubePublishingOptionsLoaded(",
        "containsSyntheticMedia",
        "session.authorizePublishing(",
        "showFinalPublishConfirmation=true",
        "session.publishPreparedReview(",
    ],
}

for relative, markers in requirements.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing UI surface: {relative}")
        continue
    compact = re.sub(r"\s+", "", path.read_text(encoding="utf-8"))
    for marker in markers:
        compact_marker = re.sub(r"\s+", "", marker)
        if compact_marker not in compact:
            errors.append(
                f"{relative}: missing active UI wiring marker: {marker}"
            )

for relative, markers in {
    "Sources/BlackstockApp/SourceDownloadManager.swift": [
        "URLSessionDownloadDelegate",
        "func pause()",
        "func resume()",
        "func cancel()",
        "didWriteData",
        "didFinishDownloadingTo",
    ],
    "Sources/BlackstockApp/IngestDirectoryWatcher.swift": [
        "DispatchSource.makeFileSystemObjectSource",
        "func start(",
        "func stop()",
    ],
}.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing UI support surface: {relative}")
        continue
    compact = re.sub(r"\s+", "", path.read_text(encoding="utf-8"))
    for marker in markers:
        compact_marker = re.sub(r"\s+", "", marker)
        if compact_marker not in compact:
            errors.append(
                f"{relative}: missing active UI support marker: {marker}"
            )

# These are intentionally implementation helpers, not separate buttons.
session = (ROOT / "Sources/BlackstockApp/BlackstockSession.swift").read_text(
    encoding="utf-8"
)
if "latestGrowthLearning=loadGrowthLearning(" not in re.sub(r"\s+", "", session):
    errors.append(
        "Growth learning must be restored when a project is selected."
    )

studio_state = (
    ROOT / "Sources/BlackstockApp/StudioState.swift"
).read_text(encoding="utf-8")
if "funcprepareShortFormSetup(){prepareOutputPreset(.shortVertical)" not in re.sub(
    r"\s+", "", studio_state
):
    errors.append(
        "Short-form helper must remain an alias of the exposed output preset path."
    )

# Paid provider adapters are not active UI features unless a separate,
# explicit user opt-in surface is introduced. They must never silently
# become the default route.
processing = (
    ROOT / "Sources/BlackstockCore/ProcessingPolicy.swift"
).read_text(encoding="utf-8")
if "allowPaidProviders: Bool = false" not in processing:
    errors.append(
        "Paid external providers must remain disabled by default."
    )

if errors:
    print("UI feature coverage audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "UI feature coverage audit passed: active Blackstock capabilities remain "
    "wired into First Run, Workspace, Studio, Packaging/Review, "
    "Published/Learning and Settings. Helper-only methods stay indirect and "
    "paid provider adapters remain opt-in/non-default."
)
