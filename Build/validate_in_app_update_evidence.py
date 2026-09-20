#!/usr/bin/env python3
import json
import math
import re
import sys
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID

def fail(message):
    print(
        f"In-app update evidence validation failed: {message}",
        file=sys.stderr,
    )
    sys.exit(1)

if len(sys.argv) != 2:
    fail("usage: validate_in_app_update_evidence.py <update-evidence.json>")

path = Path(sys.argv[1])
if not path.is_file():
    fail(f"evidence file not found: {path}")

try:
    envelope = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda token: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {token}")))
except Exception as error:
    fail(f"invalid JSON: {error}")

if envelope.get("schemaVersion") != 6:
    fail("unsupported schemaVersion")

value = envelope.get("value")
if not isinstance(value, dict):
    fail("missing evidence value")

required = [
    "id",
    "currentVersion",
    "currentBuild",
    "currentSourceCommitSHA",
    "currentExecutableSHA256",
    "currentAppPath",
    "currentApplicationTeamID",
    "currentDeveloperIDApplicationVerified",
    "currentInstallerReceiptPackageID",
    "currentInstallerReceiptVersion",
    "currentInstallerReceiptInstalledAt",
    "currentInstallerReceiptVerified",
    "manifestURL",
    "expectedInstallerTeamID",
    "startedAt",
    "targetVersion",
    "targetBuild",
    "targetSourceCommitSHA",
    "packageURL",
    "packageSHA256",
    "manifestVerifiedAt",
    "packageIntegrityVerifiedAt",
    "installerTeamVerifiedAt",
    "installerOpenedAt",
    "observedInstalledVersion",
    "observedInstalledBuild",
    "observedInstalledSourceCommitSHA",
    "observedInstalledExecutableSHA256",
    "observedInstalledAppPath",
    "observedApplicationTeamID",
    "observedDeveloperIDApplicationVerified",
    "observedInstallerReceiptPackageID",
    "observedInstallerReceiptVersion",
    "observedInstallerReceiptInstalledAt",
    "observedInstallerReceiptVerified",
    "postUpdateLaunchVerifiedAt",
]
for key in required:
    if key not in value:
        fail(f"missing completed evidence field: {key}")

version_pattern = re.compile(r"^\d+(?:\.\d+){0,3}$")
for key in ["currentVersion", "targetVersion", "observedInstalledVersion"]:
    if not version_pattern.fullmatch(str(value[key])):
        fail(f"{key} must be a numeric dotted version")

def version_tuple(raw):
    parts = [int(part) for part in str(raw).split(".")]
    return tuple(parts + [0] * (4 - len(parts)))

try:
    current_build = int(value["currentBuild"])
    target_build = int(value["targetBuild"])
    observed_build = int(value["observedInstalledBuild"])
except (TypeError, ValueError):
    fail("build fields must be integers")

if min(current_build, target_build, observed_build) <= 0:
    fail("build fields must be positive")

current_version = version_tuple(value["currentVersion"])
target_version = version_tuple(value["targetVersion"])
if target_version < current_version:
    fail("targetVersion must not be older than currentVersion")
if target_version == current_version and target_build <= current_build:
    fail("target build must be newer when version is unchanged")

if value["observedInstalledVersion"] != value["targetVersion"]:
    fail("observedInstalledVersion must equal targetVersion")
if observed_build != target_build:
    fail("observedInstalledBuild must equal targetBuild")

current_source_commit = str(value["currentSourceCommitSHA"]).strip().lower()
if not re.fullmatch(r"[0-9a-f]{40}", current_source_commit):
    fail("currentSourceCommitSHA must be a 40-character hexadecimal Git commit SHA")

current_executable_sha256 = str(value["currentExecutableSHA256"]).strip().lower()
if not re.fullmatch(r"[0-9a-f]{64}", current_executable_sha256):
    fail("currentExecutableSHA256 must be a 64-character hexadecimal SHA-256")

if str(value["currentAppPath"]).strip() != "/Applications/Blackstock.app":
    fail("currentAppPath must be /Applications/Blackstock.app")

current_team = str(value["currentApplicationTeamID"]).strip()
if not re.fullmatch(r"[A-Za-z0-9]+", current_team):
    fail("currentApplicationTeamID must be ASCII alphanumeric")

if value["currentDeveloperIDApplicationVerified"] is not True:
    fail("currentDeveloperIDApplicationVerified must be true")

if str(value["currentInstallerReceiptPackageID"]).strip() != "de.blackstock.app":
    fail("currentInstallerReceiptPackageID must equal de.blackstock.app")
if str(value["currentInstallerReceiptVersion"]).strip() != str(value["currentVersion"]):
    fail("currentInstallerReceiptVersion must equal currentVersion")
if value["currentInstallerReceiptVerified"] is not True:
    fail("currentInstallerReceiptVerified must be true")

for key in ["manifestURL", "packageURL"]:
    parsed = urlparse(str(value[key]))
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        fail(f"{key} must be an absolute HTTPS URL")
    host = parsed.hostname.rstrip(".").lower()
    if (
        host == "localhost"
        or host == "::1"
        or host.startswith("127.")
        or host.endswith(".local")
        or host.endswith(".invalid")
        or host.endswith(".example")
        or host.endswith(".test")
    ):
        fail(f"{key} must use a real production host")
    if parsed.username is not None or parsed.password is not None:
        fail(f"{key} must not contain embedded credentials")
    if parsed.fragment:
        fail(f"{key} must not contain a fragment")

try:
    UUID(str(value["id"]))
except (ValueError, TypeError):
    fail("id must be a UUID")

team = str(value["expectedInstallerTeamID"]).strip()
if not re.fullmatch(r"[A-Za-z0-9]+", team):
    fail("expectedInstallerTeamID must be ASCII alphanumeric")
if current_team != team:
    fail("currentApplicationTeamID must equal expectedInstallerTeamID")

sha = str(value["packageSHA256"]).lower()
if not re.fullmatch(r"[0-9a-f]{64}", sha):
    fail("packageSHA256 must be a 64-character hexadecimal SHA-256")

target_source_commit = str(value["targetSourceCommitSHA"]).lower()
observed_source_commit = str(value["observedInstalledSourceCommitSHA"]).lower()
for label, commit in [
    ("targetSourceCommitSHA", target_source_commit),
    ("observedInstalledSourceCommitSHA", observed_source_commit),
]:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail(f"{label} must be a 40-character hexadecimal Git commit SHA")
if observed_source_commit != target_source_commit:
    fail("observed installed source commit must equal target source commit")

observed_executable_sha256 = str(
    value["observedInstalledExecutableSHA256"]
).lower()
if not re.fullmatch(r"[0-9a-f]{64}", observed_executable_sha256):
    fail("observedInstalledExecutableSHA256 must be a 64-character hexadecimal SHA-256")

if str(value["observedInstalledAppPath"]).strip() != "/Applications/Blackstock.app":
    fail("observedInstalledAppPath must be /Applications/Blackstock.app")

observed_team = str(value["observedApplicationTeamID"]).strip()
if not re.fullmatch(r"[A-Za-z0-9]+", observed_team):
    fail("observedApplicationTeamID must be ASCII alphanumeric")
if observed_team != team:
    fail("observedApplicationTeamID must equal expectedInstallerTeamID")

if value["observedDeveloperIDApplicationVerified"] is not True:
    fail("observedDeveloperIDApplicationVerified must be true")

if str(value["observedInstallerReceiptPackageID"]).strip() != "de.blackstock.app":
    fail("observedInstallerReceiptPackageID must equal de.blackstock.app")
if str(value["observedInstallerReceiptVersion"]).strip() != str(value["targetVersion"]):
    fail("observedInstallerReceiptVersion must equal targetVersion")
if value["observedInstallerReceiptVerified"] is not True:
    fail("observedInstallerReceiptVerified must be true")

time_keys = [
    "currentInstallerReceiptInstalledAt",
    "startedAt",
    "manifestVerifiedAt",
    "packageIntegrityVerifiedAt",
    "installerTeamVerifiedAt",
    "installerOpenedAt",
    "observedInstallerReceiptInstalledAt",
    "postUpdateLaunchVerifiedAt",
]
timestamps = {}
for key in time_keys:
    raw = value[key]
    if not isinstance(raw, (int, float)):
        fail(f"{key} must use Blackstock's numeric Foundation reference timestamp")
    numeric = float(raw)
    if not math.isfinite(numeric):
        fail(f"{key} must be finite")
    timestamps[key] = numeric

ordered_keys = [
    "startedAt",
    "manifestVerifiedAt",
    "packageIntegrityVerifiedAt",
    "installerTeamVerifiedAt",
    "installerOpenedAt",
    "postUpdateLaunchVerifiedAt",
]
ordered = [timestamps[key] for key in ordered_keys]
if any(later < earlier for earlier, later in zip(ordered, ordered[1:])):
    fail("update evidence timestamps are not monotonic")

if timestamps["currentInstallerReceiptInstalledAt"] > timestamps["startedAt"] + 1:
    fail("current installer receipt must predate update start")
if (
    timestamps["observedInstallerReceiptInstalledAt"]
    <= timestamps["currentInstallerReceiptInstalledAt"]
):
    fail("target installer receipt must be newer than source receipt")
if (
    timestamps["observedInstallerReceiptInstalledAt"]
    < timestamps["installerOpenedAt"] - 1
):
    fail("target installer receipt must not predate installer handoff")
if (
    timestamps["observedInstallerReceiptInstalledAt"]
    > timestamps["postUpdateLaunchVerifiedAt"] + 1
):
    fail("target installer receipt must not postdate verified target launch")

print(
    "In-app update evidence is valid: an older Blackstock build accepted a "
    "production HTTPS manifest, verified the referenced package, handed it "
    "to the system installer, and the exact target build/source commit later launched."
)
