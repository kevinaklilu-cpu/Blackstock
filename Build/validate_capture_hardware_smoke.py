#!/usr/bin/env python3
import hashlib
import json
import math
import re
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
    data = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda token: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {token}")))
except Exception as error:
    fail(f"invalid JSON: {error}")

required_root = [
    "schemaVersion",
    "testedAt",
    "blackstockVersion",
    "blackstockBuild",
    "blackstockSourceCommitSHA",
    "macOSVersion",
    "hardwareModel",
    "installedFromPackage",
    "installerReceiptPackageID",
    "installerReceiptVersion",
    "installerReceiptVerified",
    "applicationTeamID",
    "developerIDApplicationVerified",
    "applicationExecutableSHA256",
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

if data["schemaVersion"] != 5:
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

source_commit = str(data["blackstockSourceCommitSHA"]).strip().lower()
if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    fail("blackstockSourceCommitSHA must be a 40-character hexadecimal Git commit SHA")

receipt_package_id = str(data["installerReceiptPackageID"]).strip()
receipt_version = str(data["installerReceiptVersion"]).strip()
if receipt_package_id != "de.blackstock.app":
    fail("installerReceiptPackageID must equal de.blackstock.app")
if receipt_version != str(data["blackstockVersion"]).strip():
    fail("installerReceiptVersion must equal blackstockVersion")

application_team_id = str(data["applicationTeamID"]).strip()
if not re.fullmatch(r"[A-Za-z0-9]+", application_team_id):
    fail("applicationTeamID must be non-empty ASCII alphanumeric")

application_executable_sha256 = str(
    data["applicationExecutableSHA256"]
).strip().lower()
if not re.fullmatch(r"[0-9a-f]{64}", application_executable_sha256):
    fail("applicationExecutableSHA256 must be a 64-character hexadecimal SHA-256")

for key in [
    "installedFromPackage",
    "installerReceiptVerified",
    "developerIDApplicationVerified",
    "deniedPermissionHardStopPassed",
    "temporaryCleanupPassed",
    "appRestartPersistencePassed",
]:
    if data[key] is not True:
        fail(f"{key} must be true")

projects_root = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Blackstock"
    / "Projects"
).resolve()

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
        "persistedFileSHA256",
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
        project_id = UUID(str(item["projectID"]))
        recording_launch = UUID(str(item["recordedLaunchID"]))
    except (ValueError, TypeError):
        fail(f"{name} projectID/recordedLaunchID must be UUIDs")

    persisted_path = Path(str(item["persistedFilePath"]))
    if not persisted_path.is_absolute():
        fail(f"{name}.persistedFilePath must be absolute")
    try:
        persisted_path = persisted_path.resolve(strict=True)
    except (FileNotFoundError, OSError):
        fail(f"{name}.persistedFilePath must still exist")

    expected_leaf = "Captures" if name == "microphone" else "Media"
    project_directory = persisted_path.parent.parent
    if persisted_path.parent.name != expected_leaf:
        fail(
            f"{name}.persistedFilePath must be inside the canonical "
            f"{expected_leaf} project directory"
        )
    if project_directory.parent != projects_root:
        fail(
            f"{name}.persistedFilePath must be inside Blackstock's "
            "Application Support project root"
        )
    try:
        path_project_id = UUID(project_directory.name)
        UUID(persisted_path.stem)
    except (ValueError, TypeError):
        fail(
            f"{name}.persistedFilePath must use UUID project and asset names"
        )
    if path_project_id != project_id:
        fail(
            f"{name}.persistedFilePath project does not match projectID"
        )

    expected_sha = str(item["persistedFileSHA256"]).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha):
        fail(f"{name}.persistedFileSHA256 must be a SHA-256")

    hasher = hashlib.sha256()
    with persisted_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    actual_sha = hasher.hexdigest()
    if actual_sha != expected_sha:
        fail(f"{name}.persistedFileSHA256 does not match persisted file")

    try:
        duration = float(item["durationSeconds"])
    except (TypeError, ValueError):
        fail(f"{name}.durationSeconds must be numeric")
    if not math.isfinite(duration):
        fail(f"{name}.durationSeconds must be finite")
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

    return project_id, recording_launch, persisted_path

camera_project, camera_launch, camera_path = validate_capture(
    "camera",
    require_video=True,
)
microphone_project, microphone_launch, microphone_path = validate_capture(
    "microphone",
    require_samples=True,
)
screen_project, screen_launch, screen_path = validate_capture(
    "screen",
    require_video=True,
)
system_audio_project, system_audio_launch, system_audio_path = validate_capture(
    "systemAudio",
    require_samples=True,
)

if screen_path != system_audio_path:
    fail("screen and systemAudio must reference the same ScreenCaptureKit file")

project_ids = {
    camera_project,
    microphone_project,
    screen_project,
    system_audio_project,
}
if len(project_ids) != 1:
    fail("all four canonical capture paths must belong to the same project")

recording_launches = {
    camera_launch,
    microphone_launch,
    screen_launch,
    system_audio_launch,
}
if len(recording_launches) != 1:
    fail("all four canonical capture paths must come from the same recording launch")

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
