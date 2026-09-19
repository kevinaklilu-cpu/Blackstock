#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = {
    "Sources/BlackstockCore/YouTubeAnalyticsClient.swift": [
        "case providerMayLag",
        "var temporalSemantic: TemporalSemantic",
        ".analyticsPeriod",
        "requestedStartDate",
        "requestedEndDate",
    ],
    "Sources/BlackstockCore/GrowthLoop.swift": [
        "YouTube-Analytics können verzögert sein.",
        "Analytics-Zeitraum:",
    ],
    "Tests/BlackstockCoreTests/GrowthObservationPlannerTests.swift": [
        "testTwentyFourHourWindowBecomesDueOnlyAfterElapsedTime",
        "testAnalyticsPeriodIsExplicitlyPacificCalendarDate",
        "testPlannerUsesAnalyticsPeriodSemantic",
        "testAnalyticsSnapshotRemainsExplicitAnalyticsPeriodWithLagWarning",
    ],
}

errors = []
for relative, markers in REQUIRED.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing temporal file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing temporal contract: {marker}")

if errors:
    print("Temporal semantics audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Temporal semantics audit passed: elapsed windows, provider periods and lag semantics are explicit.")