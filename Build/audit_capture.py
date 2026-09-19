#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

requirements = {
    "Sources/BlackstockCore/CaptureCapability.swift": [
        "case camera",
        "case microphone",
        "case screen",
        "case systemAudio",
        "allCanonicalCapturePathsReady",
    ],
    "Sources/BlackstockApp/CaptureCapabilityProbe.swift": [
        "AVCaptureDevice.authorizationStatus(for: .video)",
        "AVCaptureDevice.authorizationStatus(for: .audio)",
        "CGPreflightScreenCaptureAccess()",
        "CGRequestScreenCaptureAccess()",
    ],
    "Sources/BlackstockApp/CaptureCapabilityPanel.swift": [
        'GroupBox("Direkte Aufnahme")',
        '"Zugriff anfragen"',
        "CaptureKind.allCases",
    ],
    "Build/package.sh": [
        "<key>NSCameraUsageDescription</key>",
        "<key>NSMicrophoneUsageDescription</key>",
    ],
    "Tests/BlackstockCoreTests/CaptureCapabilityTests.swift": [
        "testAllCanonicalCaptureKindsAreRepresented",
        "testSnapshotRequiresEveryCanonicalPathReady",
    ],
}

errors = []
for relative, markers in requirements.items():
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing capture contract file: {relative}")
        continue
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        if marker not in text:
            errors.append(f"{relative}: missing capture contract marker: {marker}")

if errors:
    print("Capture foundation audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print("Capture foundation audit passed: four canonical capture paths are represented and permission-gated.")
