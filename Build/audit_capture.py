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
    "Sources/BlackstockCore/SupplementalCaptureAsset.swift": [
        "struct SupplementalCaptureAsset",
        "mayBeUsedInProduction",
        "rightsConfirmed",
    ],
    "Sources/BlackstockCore/StudioWorkspaceSnapshot.swift": [
        "public static let current = 5",
        "supplementalCaptures",
        "importSupplementalCapture",
        "importSupplementalVideoCapture",
        "supplementalVideoInsertSettings",
        'appendingPathComponent("Captures"',
    ],
    "Sources/BlackstockApp/CaptureCapabilityProbe.swift": [
        "AVCaptureDevice.authorizationStatus(for: .video)",
        "AVCaptureDevice.authorizationStatus(for: .audio)",
        "CGPreflightScreenCaptureAccess()",
        "CGRequestScreenCaptureAccess()",
    ],
    "Sources/BlackstockApp/CameraCaptureRecorder.swift": [
        "AVCaptureSession()",
        "AVCaptureMovieFileOutput()",
        "startRecording(",
        "stopRecording()",
        "completedRecordingURL",
    ],
    "Sources/BlackstockApp/MicrophoneCaptureRecorder.swift": [
        "AVAudioRecorder(",
        "kAudioFormatMPEG4AAC",
        "startRecording()",
        "stopRecording()",
        "completedRecordingURL",
    ],
    "Sources/BlackstockApp/ScreenCaptureRecorder.swift": [
        "SCShareableContent",
        "SCStreamConfiguration()",
        "capturesAudio = true",
        "excludesCurrentProcessAudio = true",
        "SCRecordingOutput(",
        "LegacyScreenCaptureRecordingImplementation",
        "AVAssetWriter(",
        "addStreamOutput(",
        "type: .audio",
        "startCapture()",
        "stopCapture()",
    ],
    "Sources/BlackstockApp/CaptureCapabilityPanel.swift": [
        'GroupBox("Direkte Aufnahme")',
        '"Kamera aufnehmen"',
        '"Mikrofon aufnehmen"',
        '"Bildschirm aufnehmen"',
        "onRecordedMedia(url, .camera)",
        "onRecordedMedia(url, .microphone)",
        "onRecordedMedia(url, .screen)",
    ],
    "Sources/BlackstockApp/StudioState.swift": [
        "supplementalCaptures",
        "importSupplementalCapture(",
        '"supplemental-capture-imported"',
        "supplementalVideoInsertSettings",
        "SupplementalVideoInsertInput",
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        "let isSupplementalCapture =",
        "captureKind == .microphone",
        "captureKind == .camera",
        "captureKind == .screen",
        "state.importSupplementalCapture(",
        "state.importMovie(",
        '"Video auswählen …"',
        "showOptionalCapture.toggle()",
        "if showOptionalCapture {",
        "CaptureCapabilityPanel",
        '"Zusätzliche Aufnahmen"',
        '"Als visuelle Einblendung verwenden"',
        "setSupplementalVideoEnabled",
    ],
    "Tests/BlackstockCoreTests/CaptureCapabilityTests.swift": [
        "testAllCanonicalCaptureKindsAreRepresented",
        "testSnapshotRequiresEveryCanonicalPathReady",
    ],
    "Tests/BlackstockCoreTests/StudioWorkspaceSnapshotTests.swift": [
        "testSupplementalCaptureIsCopiedIntoProjectWorkspace",
        "testVersionTwoWorkspaceEnvelopeMigratesToCurrentSchema",
        "testSupplementalCaptureRightsRoundTripInWorkspace",
    ],
    "Sources/BlackstockCore/CaptureHardwareSmokeEvidence.swift": [
        "CaptureHardwareSmokeEvidence",
        "CaptureHardwareSmokeEvidenceStore",
        "allCanonicalPathsPass",
        "recordDeniedHardStop",
        "recordTemporaryCleanup",
        "reconcileRestartPersistence",
        "persistedFilePath",
        "persistedFileSHA256",
        "blackstockSourceCommitSHA",
        "applicationTeamID",
        "developerIDApplicationVerified",
        "installerReceiptPackageID",
        "installerReceiptVersion",
        "installerReceiptInstalledAt",
        "installerReceiptVerified",
        "applicationExecutableSHA256",
        "currentSchemaVersion = 6",
    ],
    "Tests/BlackstockCoreTests/CaptureHardwareSmokeEvidenceTests.swift": [
        "testCompleteEvidenceRequiresAllFourPathsAndExternalChecks",
        "testRestartPersistenceRequiresDifferentProcessLaunch",
        "testStoreRoundTripsValidatorCompatibleShape",
    ],
    "Sources/BlackstockApp/BlackstockCaptureHardwareAudit.swift": [
        "LocalAudioSignalAnalyzer",
        "loadTracks(withMediaType: .video)",
        "recordDeniedPermission",
        "recordPersistedCapture",
        "recordTemporaryCleanup",
        "reconcilePostRestart",
        'capture-hardware-smoke.json',
        '"/Applications/Blackstock.app"',
        "operatingSystemVersionString",
        "existing.macOSVersion == osVersion",
        "installerReceiptMetadata",
        "--pkg-info-plist",
        '"de.blackstock.app"',
        '"pkg-version"',
        '"install-time"',
        "installedAtSeconds",
        '"install-location"',
        "receiptVerified",
        "CryptoKit",
        "SHA256()",
        "persistedFileSHA256",
        "BlackstockSourceCommitSHA",
        "BlackstockUpdateInstallerTeamID",
        "applicationSigningMetadata",
        "Authority=Developer ID Application",
        "TeamIdentifier=",
        '"--verify"',
        '"--deep"',
        '"--strict"',
        "verifyProcess.terminationStatus == 0",
        "isExpectedPersistedProjectCapture",
        '"Projects"',
        '"Captures"',
        '"Media"',
        "resolvingSymlinksInPath",
        "deletingPathExtension()",
    ],
    "Build/Blackstock.entitlements": [
        "com.apple.security.device.camera",
        "com.apple.security.device.audio-input",
    ],
    "Build/package.sh": [
        "<key>NSCameraUsageDescription</key>",
        "<key>NSMicrophoneUsageDescription</key>",
        "Build/Blackstock.entitlements",
        "--entitlements",
        "--options runtime",
        '--sign "$APP_SIGN_IDENTITY" "$APP"',
        '--sign - "$APP"',
    ],
    "Build/validate_capture_hardware_smoke.py": [
        "durationSeconds must be at least 5 seconds",
        "decodedSamples must be greater than zero",
        "videoTrackPresent must be true",
        "installedFromPackage",
        "appRestartPersistencePassed",
        "persistedFileSHA256 does not match persisted file",
        "restartVerifiedLaunchID",
        "blackstockSourceCommitSHA",
        "40-character hexadecimal Git commit SHA",
        "installerReceiptPackageID",
        "installerReceiptVersion",
        "installerReceiptVerified",
        "applicationTeamID",
        "developerIDApplicationVerified",
        "applicationExecutableSHA256",
        "installerReceiptInstalledAt must be ISO-8601",
        "installerReceiptInstalledAt must include a timezone",
        "installerReceiptInstalledAt must not postdate testedAt",
        "non-finite JSON number",
        "durationSeconds must be finite",
        "Application Support",
        "canonical",
        "project does not match projectID",
        "all four canonical capture paths must belong to the same project",
        "all four canonical capture paths must come from the same recording launch",
        "persistedFilePath must use UUID project and asset names",
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
            errors.append(
                f"{relative}: missing capture contract marker: {marker}"
            )

studio_view = (
    ROOT / "Sources/BlackstockApp/StudioView.swift"
).read_text(encoding="utf-8")
picker_start = studio_view.find("private func presentVideoPicker()")
picker_end = studio_view.find(
    "private func importPendingMedia()",
    picker_start,
)
if picker_start < 0 or picker_end < 0:
    errors.append(
        "StudioView must keep a dedicated local video-picker path"
    )
else:
    picker_block = studio_view[picker_start:picker_end]
    if "pendingCaptureKind = nil" not in picker_block:
        errors.append(
            "local video selection must remain explicitly separate from capture media"
        )
    if "requestAuthorization(" in picker_block:
        errors.append(
            "local video selection must never request camera, microphone or screen permissions"
        )
    if "CaptureCapabilityPanel" in picker_block:
        errors.append(
            "local video selection must not instantiate capture controls"
        )

capture_panel = (
    ROOT / "Sources/BlackstockApp/CaptureCapabilityPanel.swift"
).read_text(encoding="utf-8")
task_start = capture_panel.find(".task {")
task_end = capture_panel.find(".onChange(", task_start)
if task_start < 0 or task_end < 0:
    errors.append(
        "CaptureCapabilityPanel must keep its passive status-inspection task"
    )
else:
    passive_task = capture_panel[task_start:task_end]
    if "inspect()" not in passive_task:
        errors.append(
            "CaptureCapabilityPanel task must only inspect current permission state"
        )
    if "requestAuthorization(" in passive_task:
        errors.append(
            "CaptureCapabilityPanel must never request privacy permissions automatically on appearance"
        )

package_script = (ROOT / "Build/package.sh").read_text(
    encoding="utf-8"
)
entitlement_flag = '--entitlements "$ROOT/Build/Blackstock.entitlements"'
if package_script.count(entitlement_flag) < 2:
    errors.append(
        "Build/package.sh: capture entitlements must be applied to both "
        "Developer ID and ad-hoc app signing paths"
    )

developer_id_start = package_script.find(
    'if [[ -n "$APP_SIGN_IDENTITY" ]]; then'
)
developer_id_end = package_script.find(
    "\nelse\n",
    developer_id_start,
)
if developer_id_start < 0 or developer_id_end < 0:
    errors.append(
        "Build/package.sh: Developer ID Application signing branch is missing"
    )
else:
    developer_id_block = package_script[
        developer_id_start:developer_id_end
    ]
    for marker in [
        "codesign --force --options runtime --timestamp",
        '--entitlements "$ROOT/Build/Blackstock.entitlements"',
        '--sign "$APP_SIGN_IDENTITY" "$APP"',
    ]:
        if marker not in developer_id_block:
            errors.append(
                "Build/package.sh: Developer ID Application signing path must "
                "include Hardened Runtime and capture entitlements"
            )
            break

adhoc_contract = "\n".join([
    "  codesign --force --options runtime \\",
    '    --requirements "$ROOT/Build/Blackstock.requirements" \\',
    '    --entitlements "$ROOT/Build/Blackstock.entitlements" \\',
    '    --sign - "$APP"',
])
if adhoc_contract not in package_script:
    errors.append(
        "Build/package.sh: ad-hoc CI signing path must include Hardened "
        "Runtime and capture entitlements"
    )

# Helpers need their own JIT/library entitlements. Recursively re-signing the
# bundle would replace these with the application's capture entitlements.
for marker in [
    'for helper in yt-dlp deno; do',
    '--entitlements "$ROOT/Build/DownloadTools.entitlements"',
    '--sign "$APP_SIGN_IDENTITY" "$APP/Contents/Helpers/$helper"',
    '--sign - "$APP/Contents/Helpers/$helper"',
    'codesign --verify --deep --strict "$APP"',
]:
    if marker not in package_script:
        errors.append("Build/package.sh: missing explicit helper signing or deep verification: " + marker)
if "codesign --force --deep" in package_script:
    errors.append("Build/package.sh: recursive signing must not overwrite helper entitlements")

if errors:
    print("Capture audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Capture audit passed: camera, microphone and screen/system-audio "
    "recording paths are permission-gated, file-backed and project-bound."
)
