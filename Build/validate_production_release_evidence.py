#!/usr/bin/env python3
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

def fail(message):
    print(
        f"Production release evidence validation failed: {message}",
        file=sys.stderr,
    )
    sys.exit(1)

if len(sys.argv) != 2:
    fail("usage: validate_production_release_evidence.py <release-evidence.json>")

path = Path(sys.argv[1])
if not path.is_file():
    fail(f"evidence file not found: {path}")

try:
    data = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda token: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {token}")))
except Exception as error:
    fail(f"invalid JSON: {error}")

required = [
    "schemaVersion",
    "verifiedAt",
    "manifestURL",
    "packageURL",
    "currentVersion",
    "currentBuild",
    "targetVersion",
    "targetBuild",
    "packageSHA256",
    "sourceCommitSHA",
    "installerTeamID",
    "manifestSignatureVerified",
    "updateAvailabilityVerified",
    "packageHashVerified",
    "developerIDInstallerVerified",
    "staplerValidated",
    "gatekeeperInstallerAccepted",
    "installedAppPath",
    "installedAppVersion",
    "installedAppBuild",
    "installedAppSourceCommitSHA",
    "installedAppExecutableSHA256",
    "cameraEntitlementVerified",
    "audioInputEntitlementVerified",
    "developerIDApplicationVerified",
    "gatekeeperApplicationAccepted",
    "notarySubmissionID",
    "notaryStatus",
]
for key in required:
    if key not in data:
        fail(f"missing field: {key}")

if data["schemaVersion"] != 3:
    fail("unsupported schemaVersion")

try:
    datetime.fromisoformat(str(data["verifiedAt"]).replace("Z", "+00:00"))
except ValueError:
    fail("verifiedAt must be ISO-8601")

for key in ["manifestURL", "packageURL"]:
    parsed = urlparse(str(data[key]))
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

version_pattern = re.compile(r"^\d+(?:\.\d+){0,3}$")
for key in ["currentVersion", "targetVersion", "installedAppVersion"]:
    if not version_pattern.fullmatch(str(data[key])):
        fail(f"{key} must be a numeric dotted version")

def version_tuple(value):
    values = [int(part) for part in str(value).split(".")]
    return tuple(values + [0] * (4 - len(values)))

try:
    current_build = int(data["currentBuild"])
    target_build = int(data["targetBuild"])
    installed_app_build = int(data["installedAppBuild"])
except (TypeError, ValueError):
    fail("build values must be integers")

if current_build <= 0 or target_build <= 0 or installed_app_build <= 0:
    fail("build values must be positive")

current_version = version_tuple(data["currentVersion"])
target_version = version_tuple(data["targetVersion"])
if target_version < current_version:
    fail("targetVersion must not be older than currentVersion")
if target_version == current_version and target_build <= current_build:
    fail("target build must be newer when version is unchanged")

if str(data["installedAppVersion"]) != str(data["targetVersion"]):
    fail("installedAppVersion must equal targetVersion")
if installed_app_build != target_build:
    fail("installedAppBuild must equal targetBuild")

sha = str(data["packageSHA256"]).lower()
if not re.fullmatch(r"[0-9a-f]{64}", sha):
    fail("packageSHA256 must be a 64-character hexadecimal SHA-256")

source_commit = str(data["sourceCommitSHA"]).lower()
installed_source_commit = str(data["installedAppSourceCommitSHA"]).lower()
for label, value in [
    ("sourceCommitSHA", source_commit),
    ("installedAppSourceCommitSHA", installed_source_commit),
]:
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        fail(f"{label} must be a 40-character hexadecimal Git commit SHA")
if installed_source_commit != source_commit:
    fail("installedAppSourceCommitSHA must equal sourceCommitSHA")

installed_executable_sha256 = str(
    data["installedAppExecutableSHA256"]
).strip().lower()
if not re.fullmatch(r"[0-9a-f]{64}", installed_executable_sha256):
    fail("installedAppExecutableSHA256 must be a 64-character hexadecimal SHA-256")

team = str(data["installerTeamID"]).strip()
if not re.fullmatch(r"[A-Za-z0-9]+", team):
    fail("installerTeamID must be non-empty ASCII alphanumeric")

for key in [
    "manifestSignatureVerified",
    "updateAvailabilityVerified",
    "packageHashVerified",
    "developerIDInstallerVerified",
    "staplerValidated",
    "gatekeeperInstallerAccepted",
    "cameraEntitlementVerified",
    "audioInputEntitlementVerified",
    "developerIDApplicationVerified",
    "gatekeeperApplicationAccepted",
]:
    if data[key] is not True:
        fail(f"{key} must be true")

if str(data["installedAppPath"] or "").strip() != "/Applications/Blackstock.app":
    fail("installedAppPath must be /Applications/Blackstock.app")

if not str(data["notarySubmissionID"] or "").strip():
    fail("notarySubmissionID must be present")

if str(data["notaryStatus"]).casefold() != "accepted":
    fail("notaryStatus must be Accepted")

print(
    "Production release evidence is valid for signing, notarization, "
    "Gatekeeper and remote update-artifact integrity. "
    "A separate real in-app update smoke is still required for Updater PASS."
)
