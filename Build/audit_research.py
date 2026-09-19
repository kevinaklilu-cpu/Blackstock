#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = {
    "Sources/BlackstockCore/ResearchDecisionStore.swift": [
        "ResearchEvidenceRecord",
        "providerFacts: [String]",
        "creatorNotes: String",
        "researchQuestion: String",
        "AnalysisDecisionRecord",
        "riskOrUnknown: String",
        "options: [.atomic]",
    ],
    "Tests/BlackstockCoreTests/ResearchDecisionStoreTests.swift": [
        "testResearchAndAnalysisRoundTripPerProject",
        "testResearchCompletenessRequiresQuestionFactsAndCreatorNotes",
        "testAnalysisCompletenessRequiresRationaleAndExplicitUnknown",
    ],
    "Sources/BlackstockCore/OpportunityProjectFactory.swift": [
        "stage: .research",
        "externalID: videoID",
        "discoveredAt: opportunity.retrievedAt",
    ],
    "Sources/BlackstockApp/BlackstockSession.swift": [
        "providerFacts(",
        "completeResearch(",
        "project.stage == .research",
        "advanceActiveProject(to: .analysis)",
        "completeAnalysis(",
        "project.stage == .analysis",
        "decision == .pursue",
        "advanceActiveProject(to: .production)",
    ],
    "Sources/BlackstockApp/BlackstockApp.swift": [
        "Eingefrorene Provider-Fakten",
        "Provider-Fakten werden nicht überschrieben.",
        "Recherche abschließen und analysieren",
        "Offenes Risiko oder unbekannter Punkt",
    ],
}

errors=[]
for relative, markers in REQUIRED.items():
    path=ROOT/relative
    if not path.is_file():
        errors.append(f"missing research file: {relative}")
        continue
    text=path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing research contract: {marker}")

if errors:
    print("Research audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)
print("Research audit passed: provider facts and creator interpretation stay separate and stage-gated.")