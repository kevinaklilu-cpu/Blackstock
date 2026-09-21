#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
PIN_PATTERN = re.compile(r"^[^\s@]+/[^\s@]+@[0-9a-fA-F]{40}(?:\s+#.*)?$")
USES_PATTERN = re.compile(r"^\s*-?\s*uses:\s*([^\s]+(?:\s+#.*)?)\s*$")

errors = []
WRITE_ALLOWED_WORKFLOW = Path(".github/workflows/production-release.yml")
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
        lines = text.splitlines()

        if "pull_request_target:" in text:
            errors.append(
                f"{path.relative_to(ROOT)}: pull_request_target is forbidden "
                "because it can combine untrusted PR context with privileged workflow execution"
            )

        if re.search(r"runs-on:\s*[^\n]*-latest\b", text):
            errors.append(
                f"{path.relative_to(ROOT)}: moving *-latest runner labels are forbidden"
            )

        macos_job_count = len(
            re.findall(
                r"runs-on:\s*macos-26(?:-intel)?\b",
                text,
            )
        )
        if macos_job_count:
            if (
                "DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer"
                not in text
            ):
                errors.append(
                    f"{path.relative_to(ROOT)}: macos-26 workflows must pin Xcode 26.6"
                )
            guard_count = text.count("- name: Pinned macOS toolchain guard")
            if guard_count != macos_job_count:
                errors.append(
                    f"{path.relative_to(ROOT)}: expected one pinned toolchain guard "
                    f"per pinned macOS job ({macos_job_count}), found {guard_count}"
                )

        relative = path.relative_to(ROOT)
        write_allowed = relative == WRITE_ALLOWED_WORKFLOW
        required_permission = (
            "permissions:\n  contents: write"
            if write_allowed
            else "permissions:\n  contents: read"
        )
        if required_permission not in text:
            errors.append(
                f"{relative}: workflow must declare the expected top-level "
                f"permission ({'contents: write' if write_allowed else 'contents: read'})"
            )
        if write_allowed and (
            "pull_request:" in text
            or "pull_request_target:" in text
            or re.search(r"(?m)^\s*push:\s*$", text)
        ):
            errors.append(
                f"{relative}: the sole write-capable workflow must remain "
                "manual workflow_dispatch only"
            )

        for permission_line_number, permission_line in enumerate(lines, 1):
            normalized = permission_line.strip().lower()
            is_write_permission = (
                normalized == "permissions: write-all"
                or re.fullmatch(
                    r"[a-z0-9_-]+:\s*write(?:\s*#.*)?",
                    normalized,
                )
                or (
                    normalized.startswith("permissions:")
                    and "write" in normalized
                )
            )
            allowed_release_write = (
                write_allowed
                and normalized == "contents: write"
            )
            if is_write_permission and not allowed_release_write:
                errors.append(
                    f"{path.relative_to(ROOT)}:{permission_line_number}: "
                    f"write-capable GITHUB_TOKEN permission is forbidden: "
                    f"{permission_line.strip()}"
                )
        for line_number, line in enumerate(lines, 1):
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

            if reference.startswith("actions/checkout@"):
                base_indent = len(line) - len(line.lstrip())
                block = []
                for following in lines[line_number:]:
                    stripped = following.lstrip()
                    indent = len(following) - len(stripped)
                    if (
                        stripped.startswith("- ")
                        and indent <= base_indent
                    ):
                        break
                    block.append(following)
                if not any(
                    re.fullmatch(
                        r"\s*persist-credentials:\s*false\s*",
                        candidate,
                    )
                    for candidate in block
                ):
                    errors.append(
                        f"{path.relative_to(ROOT)}:{line_number}: "
                        "actions/checkout must set persist-credentials: false"
                    )

if errors:
    print("GitHub Actions supply-chain audit failed:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)

print(
    "GitHub Actions supply-chain audit passed: every external workflow "
    "dependency is pinned to an immutable 40-character commit SHA, "
    "checkout credentials are not persisted, runner/toolchain versions are "
    "pinned; token permissions remain read-only except for the explicit "
    "manual production-release workflow, which may use only contents: write."
)
