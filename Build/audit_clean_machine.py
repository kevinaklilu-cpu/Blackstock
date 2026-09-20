#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

requirements = {
    "Package.swift": [
        'name: "BlackstockE2ESmoke"',
    ],
    "Sources/BlackstockE2ESmoke/BlackstockE2ESmoke.swift": [
        "BLACKSTOCK_E2E_PASS",
        "SyntheticMediaFactory",
        "LocalVideoRenderer()",
        "LocalAudioTechnicalInspector()",
        "LocalAudioSignalAnalyzer()",
        "LocalLoudnessAnalyzer()",
        "YouTubeResumableUploader(",
        "ExternalActionJournal",
        "YouTubeAnalyticsClient(",
        "GrowthLearningEngine()",
        "persistenceRoundTrip",
    ],
    "Build/package.sh": [
        "BLACKSTOCK_INCLUDE_E2E_SMOKE",
        "Contents/Helpers/BlackstockE2ESmoke",
        "--arch arm64",
        "--arch x86_64",
        "lipo -create",
        "require_universal_binary",
    ],
    ".github/workflows/ci.yml": [
        'BLACKSTOCK_INCLUDE_E2E_SMOKE: "1"',
        "Run installed creator-loop E2E",
        "/Applications/Blackstock.app/Contents/Helpers/BlackstockE2ESmoke",
        "lipo -verify_arch arm64 x86_64 /Applications/Blackstock.app/Contents/MacOS/Blackstock",
        "lipo -verify_arch arm64 x86_64 /Applications/Blackstock.app/Contents/Helpers/BlackstockE2ESmoke",
        "BLACKSTOCK_E2E_PASS",
        'data["renderValidated"] is True',
        'data["qualityReviewPassed"] is True',
        'data["uploadJournalCommitted"] is True',
        'data["analyticsViews"] == 1234',
        'data["persistenceRoundTrip"] is True',
        "intel-smoke:",
        "runs-on: macos-26-intel",
        "needs: package",
        "actions/download-artifact@fa0a91b85d4f404e444e00e005971372dc801d16",
        "name: Blackstock-development-pkg",
        'test "$(uname -m)" = "x86_64"',
        "Verify downloaded package identity",
        'ACTUAL_SHA="$(shasum -a 256 Blackstock.pkg',
        "Install exact package on native Intel runner",
        "Launch installed app natively on Intel",
        "Run installed creator-loop E2E natively on Intel",
        "blackstock-intel-clean-machine-e2e.json",
        "installed-release-fingerprint.json",
        "intel-installed-release-fingerprint.json",
        "Cross-architecture installed release identity mismatch",
        '"packageSHA256"',
        '"executableSHA256"',
        "Apple-Silicon fingerprint is not bound to the downloaded package",
        "Intel fingerprint is not bound to the downloaded package",
        '"installerReceiptPackageID"',
        '"installerReceiptVersion"',
        '"runnerArchitecture"',
    ],
}

for relative, markers in requirements.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing clean-machine E2E file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing E2E contract marker: {marker}")

ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
for job_marker in ["\n  test:\n", "\n  package:\n", "\n  intel-smoke:\n"]:
    count = ci.count(job_marker)
    if count != 1:
        errors.append(
            f"canonical CI must contain {job_marker.strip()!r} exactly once; "
            f"found {count}"
        )

package = (ROOT / "Build/package.sh").read_text(encoding="utf-8")
if 'INCLUDE_E2E_SMOKE="${BLACKSTOCK_INCLUDE_E2E_SMOKE:-0}"' not in package:
    errors.append("E2E helper must remain opt-in and absent from production packages by default")

if errors:
    print("Clean-machine E2E audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Clean-machine E2E audit passed: CI installs the package and runs the "
    "opt-in creator-loop helper from /Applications with Universal-2 binaries "
    "on both native Apple-Silicon and Intel runners, real local media "
    "processing and mocked external HTTP boundaries."
)
