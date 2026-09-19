#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
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
        return path, json.loads(path.read_text(encoding="utf-8"))
    except Exception as error:
        fail(f"{label} is invalid JSON: {error}")

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

def main():
    args = parse_args()
    statuses = release_gate_statuses()
    require_internal_gates_pass(statuses)

    capture_path, capture = load_json(
        args.capture_evidence,
        "capture evidence",
    )
    release_path, release = load_json(
        args.production_release_evidence,
        "production release evidence",
    )
    updater_path, updater_envelope = load_json(
        args.in_app_update_evidence,
        "in-app update evidence",
    )

    run_validator(
        "validate_capture_hardware_smoke.py",
        capture_path,
    )
    run_validator(
        "validate_production_release_evidence.py",
        release_path,
    )
    run_validator(
        "validate_in_app_update_evidence.py",
        updater_path,
    )

    updater = updater_envelope.get("value")
    if not isinstance(updater, dict):
        fail("in-app update evidence has no value object")

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
    if release.get("installerTeamID") != updater.get(
        "expectedInstallerTeamID"
    ):
        fail(
            "production release and updater evidence use different "
            "Apple installer team IDs"
        )
    if release.get("packageSHA256") != updater.get("packageSHA256"):
        fail(
            "production release and updater evidence refer to different "
            "package SHA-256 values"
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

    if release.get("installedAppPath") != "/Applications/Blackstock.app":
        fail(
            "production release evidence must verify "
            "/Applications/Blackstock.app"
        )

    report = {
        "schemaVersion": 2,
        "ready": True,
        "verifiedAt": datetime.now(timezone.utc).isoformat().replace(
            "+00:00",
            "Z",
        ),
        "version": release_version,
        "build": release_build,
        "installerTeamID": release.get("installerTeamID"),
        "manifestURL": release.get("manifestURL"),
        "packageURL": release.get("packageURL"),
        "packageSHA256": release.get("packageSHA256"),
        "sourceCommitSHA": release_source_commit,
        "captureEvidence": str(capture_path),
        "productionReleaseEvidence": str(release_path),
        "inAppUpdateEvidence": str(updater_path),
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
