#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "if session.onboardingComplete",
        "FirstRunView(session: session)",
        "WorkspaceShell(",
        "GroupBox(\"Aktiver Projektpfad\")",
        "ResearchAnalysisJourneyView(",
        "session.completeResearch(",
        "session.completeAnalysis(",
        "growthLoopCard(",
        '.keyboardShortcut("k", modifiers: .command)',
        "hasActiveProject: session.activeProject?.stage",
        'title: "Studio öffnen"',
        'Label("Chancen", systemImage: "sparkle.magnifyingglass")',
        'Label("Projekte", systemImage: "tray.full")',
        "OpportunityWorkspaceView(",
        "ProjectLibraryView(",
    ],
    "Sources/BlackstockApp/WorkspaceProductViews.swift": [
        "struct OpportunityWorkspaceView",
        "Als neues Projekt übernehmen",
        "Keine erfundenen Scores",
        "struct ProjectLibraryView",
        "Neue Chance finden",
        "session.projects",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "loadWorkspaceOpportunities(",
        "selectProject(",
        '"blackstock.projects"',
        '"blackstock.projectSource.',
        "workspaceChannelID",
    ],
    "Sources/BlackstockCore/LocalClipCandidateGenerator.swift": [
        "LocalClipCandidateGenerator",
        "pauseBoundarySeconds",
        "minimumDurationSeconds",
        "maximumDurationSeconds",
        "averageConfidence",
    ],
    "Tests/BlackstockCoreTests/LocalClipCandidateGeneratorTests.swift": [
        "testPauseSeparatedSpeechCreatesMultipleCandidates",
        "testShortSpeechBlocksAreNotInventedAsCandidates",
        "testCandidateStaysInsideSourceDuration",
        "testLongContinuousSpeechIsChunkedByMaximumDuration",
    ],
    "Sources/BlackstockApp/StudioState.swift": [
        "generateLocalClipCandidates(",
        "applyLocalClipCandidate(",
        "local-clip-candidates-generated",
        "local-clip-candidate-applied",
        "previewLocalClipCandidate(",
        "restoreEditedPreview(",
        "saveLocalClipCandidate(",
        "loadSavedClipSelection(",
        "previewSavedClipSelection(",
        "renderSavedClipSelection(",
        "renderAllSavedClipSelections(",
        "applySavedClipSelection(",
        "removeSavedClipSelection(",
        "setBurnInCaptionsEnabled(",
        "setCaptionVisualStyle(",
        "prepareOutputPreset(",
        "prepareShortFormSetup()",
        "captionVisualStyle:",
        "burnInCaptions: burnInCaptionsEnabled",
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        "Lokale Clip-Kandidaten",
        "Clip-Kandidaten lokal finden",
        "Diesen Ausschnitt übernehmen",
        "Vorschau abspielen",
        "In Clip-Liste speichern",
        "Gespeicherte Clips",
        "Alle erstellen",
        "Datei erstellen",
        "Clip-Datei bereit",
        "In Timeline laden",
        "Übernehmen",
        "Zurück zur aktuellen Schnittvorschau",
        "keine Erfolgs-, Qualitäts- oder Viralitätsnote",
        "Sichtbare Untertitel ins Video rendern",
        "Untertitelstil",
        "Ausgabe-Preset vorbereiten",
        "YouTube 16:9, Shorts/Reels 9:16 oder Social 1:1",
        "captionPreviewOverlay",
    ],
    "Sources/BlackstockCore/LocalCaptionBurnInRenderer.swift": [
        "CaptionBurnInPlanner",
        "LocalCaptionBurnInRenderer",
        "AVVideoCompositionCoreAnimationTool",
        "AVCoreAnimationBeginTimeAtZero",
    ],
    "Tests/BlackstockCoreTests/CaptionBurnInPlannerTests.swift": [
        "testPlannerKeepsValidTranscriptTiming",
        "testPlannerClampsCaptionAtOutputEnd",
        "testPlannerDropsEmptyAndOutOfRangeSegments",
    ],
    "Sources/BlackstockCore/ClipTranscriptProjector.swift": [
        "ClipTranscriptProjector",
        "clipStart",
        "clipEnd",
        "overlapStart",
        "overlapEnd",
    ],
    "Tests/BlackstockCoreTests/ClipTranscriptProjectorTests.swift": [
        "testProjectionRebasesSegmentsToClipStart",
        "testProjectionClampsSegmentAtClipEnd",
        "testProjectionDoesNotInventMissingSegments",
    ],
    "Sources/BlackstockCore/SavedClipSelection.swift": [
        "SavedClipSelection",
        "transcriptPreview",
        "wordCount",
        "transcript",
        "renderArtifact",
        "savedAt",
    ],
    "Sources/BlackstockCore/CreatorOutputPreset.swift": [
        "CreatorOutputPreset",
        "youtubeLandscape",
        "shortVertical",
        "squareSocial",
        "prefersVisibleCaptions",
    ],
    "Tests/BlackstockCoreTests/CreatorOutputPresetTests.swift": [
        "testLandscapePresetMapsToLandscapeAndClearCaptions",
        "testShortPresetMapsToPortraitAndStrongCaptions",
        "testSquarePresetMapsToSquareAndVisibleCaptions",
    ],
    "Sources/BlackstockCore/ProjectJourneyGuidance.swift": [
        "case .discovery:",
        "case .research:",
        "case .analysis:",
        "case .production:",
        "case .preview:",
        "case .storyboard:",
        "case .editing:",
        "case .packaging:",
        "case .review:",
        "case .publishing:",
        "case .published:",
        "recommendedSurface: .overview",
        "recommendedSurface: .studio",
        "canonicalProgressPosition",
        "canonicalProgressCount",
    ],
    "Tests/BlackstockCoreTests/ProjectJourneyGuidanceTests.swift": [
        "testEveryCanonicalStageHasGuidance",
        "testImplementedProductionFlowPointsToStudio",
        "testDiscoveryDoesNotInventUnavailableProjectNavigation",
        "testResearchAndAnalysisUseOverviewEvidenceSurface",
        "testPublishedGuidanceStaysInLearningOverview",
        "testCanonicalProgressPositionsMatchStageOrder",
    ],
}

errors = []

for relative, markers in checks.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing journey contract source: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing journey contract marker: {marker}")

guidance_path = ROOT / "Sources/BlackstockCore/ProjectJourneyGuidance.swift"
if guidance_path.is_file():
    guidance = guidance_path.read_text(encoding="utf-8")
    studio_stages = [
        ".production", ".preview", ".storyboard", ".editing",
        ".packaging", ".review", ".publishing",
    ]
    for stage in studio_stages:
        stage_start = guidance.find(f"case {stage}:")
        if stage_start < 0:
            continue
        next_case = guidance.find("\n        case .", stage_start + 1)
        block = guidance[stage_start: next_case if next_case >= 0 else len(guidance)]
        if "recommendedSurface: .studio" not in block:
            errors.append(f"{stage}: production-stage journey must route to Studio")

    for stage in [".research", ".analysis", ".published"]:
        stage_start = guidance.find(f"case {stage}:")
        if stage_start < 0:
            continue
        next_case = guidance.find("\n        case .", stage_start + 1)
        block = guidance[stage_start: next_case if next_case >= 0 else len(guidance)]
        if "recommendedSurface: .overview" not in block:
            errors.append(f"{stage}: journey must route to Overview")

app_path = ROOT / "Sources/BlackstockApp/BlackstockApp.swift"
if app_path.is_file():
    app = app_path.read_text(encoding="utf-8")
    if 'if session.activeProject?.stage.journeyGuidance\n                    .recommendedSurface == .studio' not in app:
        errors.append("Studio navigation must remain capability/stage gated")
    if 'project.stage == .research\n                || project.stage == .analysis' not in app:
        errors.append("Research and analysis must expose guided overview UI")
    if 'project.stage == .published' not in app:
        errors.append("Published stage must expose learning UI")

if errors:
    print("Journey audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Journey audit passed: first run, persistent opportunities/projects, evidence stages, Studio flow and learning surface remain connected.")
