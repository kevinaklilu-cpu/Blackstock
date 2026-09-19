#!/usr/bin/env python3
import json
import sys
from datetime import datetime
from pathlib import Path
from uuid import UUID

def fail(message):
    print(f"Capture hardware smoke validation failed: {message}", file=sys.stderr)
    sys.exit(1)

if len(sys.argv) != 2:
    fail("usage: validate_capture_hardware_smoke.py <evidence.json>")

path = Path(sys.argv[1])
if not path.is_file():
    fail(f"evidence file not found: {path}")

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as error:
    fail(f"invalid JSON: {error}")

required_root = [
    "schemaVersion",
    "testedAt",
    "blackstockVersion",
    "blackstockBuild",
    "macOSVersion",
    "hardwareModel",
    "installedFromPackage",
    "camera",
    "microphone",
    "screen",
    "systemAudio",
    "deniedPermissionHardStopPassed",
    "temporaryCleanupPassed",
    "appRestartPersistencePassed",
    "restartVerifiedLaunchID",
    "deniedPermissionKinds",
    "temporaryCleanupKinds",
]
for key in required_root:
    if key not in data:
        fail(f"missing field: {key}")

if data["schemaVersion"] != 1:
    fail("unsupported schemaVersion")

try:
    datetime.fromisoformat(str(data["testedAt"]).replace("Z", "+00:00"))
except ValueError:
    fail("testedAt must be ISO-8601")

for key in ["blackstockVersion", "blackstockBuild", "macOSVersion", "hardwareModel"]:
    value = str(data[key]).strip()
    if not value:
        fail(f"{key} must not be empty")
    if value.upper() == "UNBEKANNT":
        fail(f"{key} must not be unknown")

for key in [
    "installedFromPackage",
    "deniedPermissionHardStopPassed",
    "temporaryCleanupPassed",
    "appRestartPersistencePassed",
]:
    if data[key] is not True:
        fail(f"{key} must be true")

def validate_capture(name, require_video=False, require_samples=False):
    item = data.get(name)
    if not isinstance(item, dict):
        fail(f"{name} must be an object")

    for key in [
        "permissionGranted",
        "recordingCreated",
        "durationSeconds",
        "persistedToProject",
        "projectID",
        "recordedLaunchID",
        "persistedFilePath",
    ]:
        if key not in item:
            fail(f"{name}.{key} is required")

    if item["permissionGranted"] is not True:
        fail(f"{name}.permissionGranted must be true")
    if item["recordingCreated"] is not True:
        fail(f"{name}.recordingCreated must be true")
    if item["persistedToProject"] is not True:
        fail(f"{name}.persistedToProject must be true")

    try:
        UUID(str(item["projectID"]))
        recording_launch = UUID(str(item["recordedLaunchID"]))
    except (ValueError, TypeError):
        fail(f"{name} projectID/recordedLaunchID must be UUIDs")

    persisted_path = Path(str(item["persistedFilePath"]))
    if not persisted_path.is_absolute():
        fail(f"{name}.persistedFilePath must be absolute")
    if not persisted_path.is_file():
        fail(f"{name}.persistedFilePath must still exist")

    try:
        duration = float(item["durationSeconds"])
    except (TypeError, ValueError):
        fail(f"{name}.durationSeconds must be numeric")
    if duration < 5:
        fail(f"{name}.durationSeconds must be at least 5 seconds")

    if require_video and item.get("videoTrackPresent") is not True:
        fail(f"{name}.videoTrackPresent must be true")

    if require_samples:
        try:
            samples = int(item.get("decodedSamples", 0))
        except (TypeError, ValueError):
            fail(f"{name}.decodedSamples must be an integer")
        if samples <= 0:
            fail(f"{name}.decodedSamples must be greater than zero")

    return recording_launch, persisted_path

camera_launch, camera_path = validate_capture(
    "camera",
    require_video=True,
)
microphone_launch, microphone_path = validate_capture(
    "microphone",
    require_samples=True,
)
screen_launch, screen_path = validate_capture(
    "screen",
    require_video=True,
)
system_audio_launch, system_audio_path = validate_capture(
    "systemAudio",
    require_samples=True,
)

if screen_path != system_audio_path:
    fail("screen and systemAudio must reference the same ScreenCaptureKit file")

try:
    restart_launch = UUID(str(data["restartVerifiedLaunchID"]))
except (ValueError, TypeError):
    fail("restartVerifiedLaunchID must be a UUID")

for capture_launch in [
    camera_launch,
    microphone_launch,
    screen_launch,
    system_audio_launch,
]:
    if capture_launch == restart_launch:
        fail("restartVerifiedLaunchID must differ from every recording launch")

required_kinds = {"camera", "microphone", "screen", "systemAudio"}
for key in ["deniedPermissionKinds", "temporaryCleanupKinds"]:
    raw = data[key]
    if not isinstance(raw, list):
        fail(f"{key} must be an array")
    if not required_kinds.issubset(set(map(str, raw))):
        fail(f"{key} must contain all four canonical capture kinds")

print("Capture hardware smoke evidence is valid.")
