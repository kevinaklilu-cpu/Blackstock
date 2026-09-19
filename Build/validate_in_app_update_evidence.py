#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

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
    envelope = json.loads(path.read_text(encoding="utf-8"))
except Exception as error:
    fail(f"invalid JSON: {error}")

if envelope.get("schemaVersion") != 2:
    fail("unsupported schemaVersion")

value = envelope.get("value")
if not isinstance(value, dict):
    fail("missing evidence value")

required = [
    "id",
    "currentVersion",
    "currentBuild",
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

for key in ["manifestURL", "packageURL"]:
    parsed = urlparse(str(value[key]))
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        fail(f"{key} must be an absolute HTTPS URL")
    host = parsed.hostname.lower()
    if (
        host == "localhost"
        or host.startswith("127.")
        or host.endswith(".invalid")
        or host.endswith(".example")
        or host.endswith(".test")
    ):
        fail(f"{key} must use a real production host")

team = str(value["expectedInstallerTeamID"]).strip()
if not re.fullmatch(r"[A-Za-z0-9]+", team):
    fail("expectedInstallerTeamID must be ASCII alphanumeric")

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

time_keys = [
    "startedAt",
    "manifestVerifiedAt",
    "packageIntegrityVerifiedAt",
    "installerTeamVerifiedAt",
    "installerOpenedAt",
    "postUpdateLaunchVerifiedAt",
]
times = []
for key in time_keys:
    raw = value[key]
    if not isinstance(raw, (int, float)):
        fail(f"{key} must use Blackstock's numeric Foundation reference timestamp")
    times.append(float(raw))

if any(later < earlier for earlier, later in zip(times, times[1:])):
    fail("update evidence timestamps are not monotonic")

print(
    "In-app update evidence is valid: an older Blackstock build accepted a "
    "production HTTPS manifest, verified the referenced package, handed it "
    "to the system installer, and the exact target build/source commit later launched."
)
