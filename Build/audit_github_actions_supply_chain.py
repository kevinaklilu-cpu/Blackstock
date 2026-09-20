#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
PIN_PATTERN = re.compile(r"^[^\s@]+/[^\s@]+@[0-9a-fA-F]{40}(?:\s+#.*)?$")
USES_PATTERN = re.compile(r"^\s*-?\s*uses:\s*([^\s]+(?:\s+#.*)?)\s*$")

errors = []
if not WORKFLOWS.is_dir():
    errors.append(".github/workflows directory is missing")
else:
    workflow_files = sorted(
        list(WORKFLOWS.glob("*.yml"))
        + list(WORKFLOWS.glob("*.yaml"))
    )
    if not workflow_files:
        errors.append("no GitHub Actions workflows found")

    for path in workflow_files:
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), 1):
            match = USES_PATTERN.match(line)
            if not match:
                continue
            reference = match.group(1).strip()
            if reference.startswith("./"):
                continue
            if reference.startswith("docker://"):
                errors.append(
                    f"{path.relative_to(ROOT)}:{line_number}: "
                    "docker:// actions are not allowed in canonical workflows"
                )
                continue
            if not PIN_PATTERN.fullmatch(reference):
                errors.append(
                    f"{path.relative_to(ROOT)}:{line_number}: "
                    f"external action is not pinned to a full commit SHA: {reference}"
                )

if errors:
    print("GitHub Actions supply-chain audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "GitHub Actions supply-chain audit passed: every external workflow "
    "dependency is pinned to an immutable 40-character commit SHA."
)
