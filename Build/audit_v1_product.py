#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def require(path: str, needles: list[str]) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise SystemExit(f"{path}: missing 1.0 contract: {missing}")


require("README.md", [
    "# Blackstock 1.0",
    "LOKALES 1.0.0-PAKET VALIDIERT",
    "ÖFFENTLICHE MACOS-FREIGABE AUSSTEHEND",
])
require("Sources/BlackstockCore/SpeechCleanup.swift", [
    "LocalSpeechCleanupPlanner",
    "sourceRanges(forOutputRange",
    "duration * 0.3",
])
require("Sources/BlackstockApp/StudioState.swift", [
    "func applySpeechCleanup() async",
    "func autoArrangeSupplementalVideos(",
    "actor: .acceptedAIProposal",
    "speech-cleanup-applied",
    "multi-source-video-auto-arranged",
])
require("Sources/BlackstockApp/StudioView.swift", [
    '"Sprachschnitt"',
    '"Vorschläge anwenden"',
    '"Automatisch anordnen"',
    "Bild und Ton werden immer gemeinsam gekürzt",
])
require("Sources/BlackstockApp/FirstRunView.swift", [
    "Desktop-OAuth-Datei hinzufügen",
    "Blackstock öffnen",
    "Videos und Mehrquellen-Stories erstellst du anschließend in Entdecken.",
])
require("Sources/BlackstockApp/BlackstockApp.swift", [
    "YouTubeEmbeddedPlayer",
    'title: "Entdecken"',
])
require("Sources/BlackstockApp/WorkspaceProductViews.swift", [
    '"Thema, Kanal oder Stichwort"',
    "await session.ensureYouTubeDiscoveryOptionsLoaded()",
    "await loadOpportunities()",
    "YouTubeEmbeddedPlayer(videoID: item.videoID)",
    "session.opportunityTimeWindow = .last7Days",
    'Picker(\n                    "Land"',
    "session.opportunityContentFilter.germanTitle",
    '"Blackstock Story-Vorschlag"',
    '"Als passendes Ergänzungsvideo wählen"',
])
require("Sources/BlackstockApp/BlackstockSession.swift", [
    "OpportunityTimeWindow = .last7Days",
    "publishedAfter: window.publishedAfter",
    "Kategorie, Sprache und Region wurden erweitert; Zeitraum und Format bleiben strikt aktiv.",
])
require("Sources/BlackstockApp/StudioView.swift", [
    "activeStorySources",
    "beginStorySourceDownloadsIfNeeded",
])
require("Sources/BlackstockApp/SourceDownloadManager.swift", [
    "func pause()",
    "func resume()",
])
require("docs/1.0_RELEASE_NOTES.md", [
    "Blackstock 1.0.0",
    "Developer-ID-Signierung",
])

print("BLACKSTOCK_V1_PRODUCT_AUDIT_PASS")
