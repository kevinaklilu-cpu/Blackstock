#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTERNAL_GATES = {
    "Capture",
    "Signing",
    "Notarization",
    "Gatekeeper",
    "Updater",
}

def fail(message):
    print(
        f"Blackstock market-readiness verification failed: {message}",
        file=sys.stderr,
    )
    sys.exit(1)

def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Verify Blackstock's internal release gates together with "
            "real external capture, Apple release and in-app update evidence."
        )
    )
    parser.add_argument("--capture-evidence", required=True)
    parser.add_argument("--production-release-evidence", required=True)
    parser.add_argument("--in-app-update-evidence", required=True)
    parser.add_argument("--output")
    return parser.parse_args()

def load_json(path_value, label):
    path = Path(path_value).expanduser().resolve()
    if not path.is_file():
        fail(f"{label} file not found: {path}")
    try:
        raw = path.read_bytes()
        data = json.loads(
            raw.decode("utf-8"),
            parse_constant=lambda token: (_ for _ in ()).throw(
                ValueError(f"non-finite JSON number: {token}")
            ),
        )
        digest = hashlib.sha256(raw).hexdigest()
        return path, data, raw, digest
    except Exception as error:
        fail(f"{label} is invalid JSON: {error}")

def write_snapshot(directory, name, raw):
    snapshot = Path(directory) / name
    snapshot.write_bytes(raw)
    return snapshot

def require_source_unchanged(path, expected_sha256, label):
    try:
        current = hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        fail(f"{label} changed or disappeared during verification: {error}")
    if current != expected_sha256:
        fail(f"{label} changed during verification")

def run_validator(script_name, evidence_path):
    script = ROOT / "Build" / script_name
    result = subprocess.run(
        [sys.executable, str(script), str(evidence_path)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        fail(
            f"{script_name} rejected {evidence_path}: "
            f"{result.stdout.strip()}"
        )

def release_gate_statuses():
    path = ROOT / "docs" / "RELEASE_GATES.md"
    text = path.read_text(encoding="utf-8")
    statuses = {}
    for line in text.splitlines():
        match = re.fullmatch(
            r"\|\s*([^|]+?)\s*\|\s*(PASS|FAIL|BLOCKED_EXTERNAL)\s*\|",
            line,
        )
        if match:
            statuses[match.group(1).strip()] = match.group(2)
    if not statuses:
        fail("docs/RELEASE_GATES.md contains no parseable gates")
    return statuses

def require_internal_gates_pass(statuses):
    unexpected = {
        gate: status
        for gate, status in statuses.items()
        if gate not in EXTERNAL_GATES and status != "PASS"
    }
    if unexpected:
        rendered = ", ".join(
            f"{gate}={status}" for gate, status in sorted(unexpected.items())
        )
        fail(f"internal release gates are not all PASS: {rendered}")

    missing = EXTERNAL_GATES.difference(statuses)
    if missing:
        fail(
            "release gate table is missing expected external gates: "
            + ", ".join(sorted(missing))
        )

def as_positive_int(value, label):
    try:
        result = int(value)
    except (TypeError, ValueError):
        fail(f"{label} must be an integer")
    if result <= 0:
        fail(f"{label} must be positive")
    return result

def normalize_version(value, label):
    value = str(value).strip()
    if not re.fullmatch(r"\d+(?:\.\d+){0,3}", value):
        fail(f"{label} must be a numeric dotted version")
    return value

def normalize_source_commit(value, label):
    value = str(value).strip().lower()
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        fail(f"{label} must be a 40-character hexadecimal Git commit SHA")
    return value

def normalize_sha256(value, label):
    value = str(value).strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        fail(f"{label} must be a 64-character hexadecimal SHA-256")
    return value

def main():
    args = parse_args()
    statuses = release_gate_statuses()
    require_internal_gates_pass(statuses)

    (
        capture_path,
        capture,
        capture_raw,
        capture_sha256,
    ) = load_json(
        args.capture_evidence,
        "capture evidence",
    )
    (
        release_path,
        release,
        release_raw,
        release_sha256,
    ) = load_json(
        args.production_release_evidence,
        "production release evidence",
    )
    (
        updater_path,
        updater_envelope,
        updater_raw,
        updater_sha256,
    ) = load_json(
        args.in_app_update_evidence,
        "in-app update evidence",
    )

    with tempfile.TemporaryDirectory(
        prefix="blackstock-market-readiness-"
    ) as snapshot_directory:
        capture_snapshot = write_snapshot(
            snapshot_directory,
            "capture-evidence.json",
            capture_raw,
        )
        release_snapshot = write_snapshot(
            snapshot_directory,
            "production-release-evidence.json",
            release_raw,
        )
        updater_snapshot = write_snapshot(
            snapshot_directory,
            "in-app-update-evidence.json",
            updater_raw,
        )

        run_validator(
            "validate_capture_hardware_smoke.py",
            capture_snapshot,
        )
        run_validator(
            "validate_production_release_evidence.py",
            release_snapshot,
        )
        run_validator(
            "validate_in_app_update_evidence.py",
            updater_snapshot,
        )

    require_source_unchanged(
        capture_path,
        capture_sha256,
        "capture evidence",
    )
    require_source_unchanged(
        release_path,
        release_sha256,
        "production release evidence",
    )
    require_source_unchanged(
        updater_path,
        updater_sha256,
        "in-app update evidence",
    )

    updater = updater_envelope.get("value")
    if not isinstance(updater, dict):
        fail("in-app update evidence has no value object")

    release_current_version = normalize_version(
        release.get("currentVersion"),
        "release.currentVersion",
    )
    updater_current_version = normalize_version(
        updater.get("currentVersion"),
        "updater.currentVersion",
    )
    if release_current_version != updater_current_version:
        fail(
            "production release and updater evidence do not refer to "
            "the same source update version"
        )

    capture_version = normalize_version(
        capture.get("blackstockVersion"),
        "capture.blackstockVersion",
    )
    release_version = normalize_version(
        release.get("targetVersion"),
        "release.targetVersion",
    )
    updater_version = normalize_version(
        updater.get("targetVersion"),
        "updater.targetVersion",
    )
    observed_version = normalize_version(
        updater.get("observedInstalledVersion"),
        "updater.observedInstalledVersion",
    )

    release_current_build = as_positive_int(
        release.get("currentBuild"),
        "release.currentBuild",
    )
    updater_current_build = as_positive_int(
        updater.get("currentBuild"),
        "updater.currentBuild",
    )
    if release_current_build != updater_current_build:
        fail(
            "production release and updater evidence do not refer to "
            "the same source update build"
        )

    capture_build = as_positive_int(
        capture.get("blackstockBuild"),
        "capture.blackstockBuild",
    )
    release_build = as_positive_int(
        release.get("targetBuild"),
        "release.targetBuild",
    )
    updater_build = as_positive_int(
        updater.get("targetBuild"),
        "updater.targetBuild",
    )
    observed_build = as_positive_int(
        updater.get("observedInstalledBuild"),
        "updater.observedInstalledBuild",
    )

    versions = {
        capture_version,
        release_version,
        updater_version,
        observed_version,
    }
    builds = {
        capture_build,
        release_build,
        updater_build,
        observed_build,
    }
    if len(versions) != 1 or len(builds) != 1:
        fail(
            "capture, production release and updater evidence do not "
            "refer to the same exact Blackstock version/build"
        )

    if release.get("manifestURL") != updater.get("manifestURL"):
        fail(
            "production release and in-app updater evidence use "
            "different manifest URLs"
        )
    if release.get("packageURL") != updater.get("packageURL"):
        fail(
            "production release and in-app updater evidence use "
            "different package URLs"
        )
    release_team_id = str(
        release.get("installerTeamID", "")
    ).strip()
    capture_team_id = str(
        capture.get("applicationTeamID", "")
    ).strip()
    updater_team_id = str(
        updater.get("expectedInstallerTeamID", "")
    ).strip()
    updater_observed_team_id = str(
        updater.get("observedApplicationTeamID", "")
    ).strip()
    if len({
        release_team_id,
        capture_team_id,
        updater_team_id,
        updater_observed_team_id,
    }) != 1:
        fail(
            "capture, production release and updater evidence use "
            "different Apple team IDs"
        )
    if release.get("packageSHA256") != updater.get("packageSHA256"):
        fail(
            "production release and updater evidence refer to different "
            "package SHA-256 values"
        )

    updater_current_source_commit = normalize_source_commit(
        updater.get("currentSourceCommitSHA"),
        "updater.currentSourceCommitSHA",
    )
    updater_current_executable_sha256 = normalize_sha256(
        updater.get("currentExecutableSHA256"),
        "updater.currentExecutableSHA256",
    )

    capture_source_commit = normalize_source_commit(
        capture.get("blackstockSourceCommitSHA"),
        "capture.blackstockSourceCommitSHA",
    )
    release_source_commit = normalize_source_commit(
        release.get("sourceCommitSHA"),
        "release.sourceCommitSHA",
    )
    installed_source_commit = normalize_source_commit(
        release.get("installedAppSourceCommitSHA"),
        "release.installedAppSourceCommitSHA",
    )
    updater_target_source_commit = normalize_source_commit(
        updater.get("targetSourceCommitSHA"),
        "updater.targetSourceCommitSHA",
    )
    updater_observed_source_commit = normalize_source_commit(
        updater.get("observedInstalledSourceCommitSHA"),
        "updater.observedInstalledSourceCommitSHA",
    )
    source_commits = {
        capture_source_commit,
        release_source_commit,
        installed_source_commit,
        updater_target_source_commit,
        updater_observed_source_commit,
    }
    if len(source_commits) != 1:
        fail(
            "capture, production release and updater evidence do not "
            "refer to the same exact source commit"
        )

    capture_executable_sha256 = normalize_sha256(
        capture.get("applicationExecutableSHA256"),
        "capture.applicationExecutableSHA256",
    )
    release_executable_sha256 = normalize_sha256(
        release.get("installedAppExecutableSHA256"),
        "release.installedAppExecutableSHA256",
    )
    updater_executable_sha256 = normalize_sha256(
        updater.get("observedInstalledExecutableSHA256"),
        "updater.observedInstalledExecutableSHA256",
    )
    if len({
        capture_executable_sha256,
        release_executable_sha256,
        updater_executable_sha256,
    }) != 1:
        fail(
            "capture, production release and updater evidence do not "
            "refer to the same exact installed Blackstock executable"
        )

    if release.get("installedAppPath") != "/Applications/Blackstock.app":
        fail(
            "production release evidence must verify "
            "/Applications/Blackstock.app"
        )
    if updater.get("observedInstalledAppPath") != release.get("installedAppPath"):
        fail(
            "production release and updater evidence do not verify "
            "the same installed app path"
        )
    if capture.get("installerReceiptPackageID") != updater.get(
        "observedInstallerReceiptPackageID"
    ):
        fail(
            "capture and updater evidence use different installer receipt package IDs"
        )
    if str(capture.get("installerReceiptVersion")) != str(
        updater.get("observedInstallerReceiptVersion")
    ):
        fail(
            "capture and updater evidence use different installer receipt versions"
        )

    try:
        capture_receipt_installed_at = datetime.fromisoformat(
            str(capture.get("installerReceiptInstalledAt", ""))
                .replace("Z", "+00:00")
        )
        updater_receipt_reference_seconds = float(
            updater.get("observedInstallerReceiptInstalledAt")
        )
        updater_receipt_installed_at = datetime.fromtimestamp(
            updater_receipt_reference_seconds + 978_307_200,
            tz=timezone.utc,
        )
    except (TypeError, ValueError, OverflowError):
        fail("installer receipt installation timestamps are invalid")
    if capture_receipt_installed_at.tzinfo is None:
        fail("capture installer receipt installation timestamp must include timezone")
    capture_receipt_installed_at = capture_receipt_installed_at.astimezone(
        timezone.utc
    )
    receipt_delta = abs(
        (
            capture_receipt_installed_at
            - updater_receipt_installed_at
        ).total_seconds()
    )
    if receipt_delta > 1:
        fail(
            "capture and updater evidence do not refer to the same "
            "installer receipt installation"
        )

    report = {
        "schemaVersion": 3,
        "ready": True,
        "verifiedAt": datetime.now(timezone.utc).isoformat().replace(
            "+00:00",
            "Z",
        ),
        "sourceVersion": release_current_version,
        "sourceBuild": release_current_build,
        "sourceAppSourceCommitSHA": updater_current_source_commit,
        "sourceAppExecutableSHA256": updater_current_executable_sha256,
        "sourceAppPath": updater.get("currentAppPath"),
        "sourceAppTeamID": updater.get("currentApplicationTeamID"),
        "sourceInstallerReceiptPackageID": updater.get(
            "currentInstallerReceiptPackageID"
        ),
        "sourceInstallerReceiptVersion": updater.get(
            "currentInstallerReceiptVersion"
        ),
        "sourceInstallerReceiptInstalledAt": updater.get(
            "currentInstallerReceiptInstalledAt"
        ),
        "version": release_version,
        "build": release_build,
        "installerTeamID": release_team_id,
        "manifestURL": release.get("manifestURL"),
        "packageURL": release.get("packageURL"),
        "packageSHA256": release.get("packageSHA256"),
        "sourceCommitSHA": release_source_commit,
        "executableSHA256": release_executable_sha256,
        "installedAppPath": release.get("installedAppPath"),
        "installedAppTeamID": updater.get("observedApplicationTeamID"),
        "installerReceiptPackageID": updater.get(
            "observedInstallerReceiptPackageID"
        ),
        "installerReceiptVersion": updater.get(
            "observedInstallerReceiptVersion"
        ),
        "installerReceiptInstalledAt": updater.get(
            "observedInstallerReceiptInstalledAt"
        ),
        "captureInstallerReceiptInstalledAt": capture.get(
            "installerReceiptInstalledAt"
        ),
        "sameInstallationReceiptVerified": True,
        "captureEvidence": str(capture_path),
        "captureEvidenceSHA256": capture_sha256,
        "productionReleaseEvidence": str(release_path),
        "productionReleaseEvidenceSHA256": release_sha256,
        "inAppUpdateEvidence": str(updater_path),
        "inAppUpdateEvidenceSHA256": updater_sha256,
        "internalGateCount": sum(
            1
            for gate, status in statuses.items()
            if gate not in EXTERNAL_GATES and status == "PASS"
        ),
        "externalEvidenceGates": sorted(EXTERNAL_GATES),
    }

    encoded = json.dumps(
        report,
        indent=2,
        sort_keys=True,
    )
    if args.output:
        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(encoded + "\n", encoding="utf-8")
        print("BLACKSTOCK_MARKET_READINESS_PASS")
        print(output)
    else:
        print("BLACKSTOCK_MARKET_READINESS_PASS")
        print(encoded)

if __name__ == "__main__":
    main()
