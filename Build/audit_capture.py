#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

studio = (ROOT / "Sources/BlackstockApp/StudioView.swift").read_text(
    encoding="utf-8"
)
for forbidden in [
    "CaptureCapabilityPanel",
    "showOptionalCapture",
    "pendingCaptureKind",
    "importSupplementalCapture(",
    'GroupBox("Zusätzliche Aufnahmen")',
    "setSupplementalAudioEnabled(",
    "setSupplementalVideoEnabled(",
]:
    if forbidden in studio:
        errors.append(
            f"StudioView must not expose capture workflow: {forbidden}"
        )

for required in [
    "presentVideoPicker()",
    "SourceDownloadManager()",
    "IngestDirectoryWatcher()",
    "attemptAutomaticOriginalBinding()",
    "Creator-Quelle laden",
    "state.importMovie(",
]:
    if required not in studio:
        errors.append(
            f"StudioView missing YouTube source workflow: {required}"
        )

package = (ROOT / "Build/package.sh").read_text(encoding="utf-8")
for forbidden in [
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
]:
    if forbidden in package:
        errors.append(
            f"package must not request unused capture permission: {forbidden}"
        )
if "NSSpeechRecognitionUsageDescription" not in package:
    errors.append(
        "speech recognition permission must remain for local captions"
    )

entitlements = (
    ROOT / "Build/Blackstock.entitlements"
).read_text(encoding="utf-8")
for forbidden in [
    "com.apple.security.device.camera",
    "com.apple.security.device.audio-input",
]:
    if forbidden in entitlements:
        errors.append(
            f"unused capture entitlement must not ship: {forbidden}"
        )

app = (
    ROOT / "Sources/BlackstockApp/BlackstockApp.swift"
).read_text(encoding="utf-8")
if "BlackstockCaptureHardwareAudit" in app:
    errors.append(
        "capture hardware diagnostics must not be exposed in Settings"
    )

session = (
    ROOT / "Sources/BlackstockApp/BlackstockSession.swift"
).read_text(encoding="utf-8")
if "BlackstockCaptureHardwareAudit.reconcilePostRestart()" in session:
    errors.append(
        "capture hardware audit must not run at app startup"
    )

if errors:
    print("YouTube-only source audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "YouTube-only source audit passed: Blackstock requests no camera or "
    "microphone access and keeps source acquisition focused on media files, "
    "creator-provided links, direct authorized downloads and ingest."
)
