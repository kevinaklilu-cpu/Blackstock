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
        "public static let current = 4",
        "supplementalCaptures",
        "importSupplementalCapture",
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
    ],
    "Sources/BlackstockApp/StudioView.swift": [
        "if captureKind == .microphone",
        "state.importSupplementalCapture(",
        "state.importMovie(",
        '"Zusätzliche Aufnahmen"',
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

package_script = (ROOT / "Build/package.sh").read_text(
    encoding="utf-8"
)
entitlement_flag = '--entitlements "$ROOT/Build/Blackstock.entitlements"'
if package_script.count(entitlement_flag) < 2:
    errors.append(
        "Build/package.sh: capture entitlements must be applied to both "
        "Developer ID and ad-hoc app signing paths"
    )

developer_id_contract = "\n".join([
    "  codesign --force --options runtime --timestamp \\",
    '    --entitlements "$ROOT/Build/Blackstock.entitlements" \\',
    '    --sign "$APP_SIGN_IDENTITY" "$APP"',
])
if developer_id_contract not in package_script:
    errors.append(
        "Build/package.sh: Developer ID Application signing path must "
        "include Hardened Runtime and capture entitlements"
    )

adhoc_contract = "\n".join([
    "  codesign --force --deep --options runtime \\",
    '    --entitlements "$ROOT/Build/Blackstock.entitlements" \\',
    '    --sign - "$APP"',
])
if adhoc_contract not in package_script:
    errors.append(
        "Build/package.sh: ad-hoc CI signing path must include Hardened "
        "Runtime and capture entitlements"
    )

if errors:
    print("Capture audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Capture audit passed: camera, microphone and screen/system-audio "
    "recording paths are permission-gated, file-backed and project-bound."
)
