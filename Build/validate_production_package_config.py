#!/usr/bin/env python3

import argparse
import base64
import binascii
import re
import sys
from urllib.parse import urlparse

FORBIDDEN_HOST_SUFFIXES = (
    ".invalid",
    ".example",
    ".test",
)

def fail(message):
    print(
        f"Production package configuration validation failed: {message}",
        file=sys.stderr,
    )
    sys.exit(1)

def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Validate fail-closed Blackstock production package "
            "update configuration before compilation/signing."
        )
    )
    parser.add_argument("--manifest-url", required=True)
    parser.add_argument("--public-key-base64", required=True)
    parser.add_argument("--installer-team-id", required=True)
    return parser.parse_args()

def validate_manifest_url(value):
    raw = value.strip()
    parsed = urlparse(raw)
    if parsed.scheme.lower() != "https" or not parsed.hostname:
        fail("update manifest URL must be an absolute HTTPS URL")

    host = parsed.hostname.rstrip(".").lower()
    if (
        host == "localhost"
        or host.startswith("127.")
        or host == "::1"
        or any(host.endswith(suffix) for suffix in FORBIDDEN_HOST_SUFFIXES)
    ):
        fail("update manifest URL must use a real production host")

    if parsed.username is not None or parsed.password is not None:
        fail("update manifest URL must not contain embedded credentials")

    if parsed.fragment:
        fail("update manifest URL must not contain a fragment")

def validate_public_key(value):
    try:
        raw = base64.b64decode(
            value.strip(),
            validate=True,
        )
    except (binascii.Error, ValueError):
        fail("update public key must be valid Base64")
    if len(raw) != 32:
        fail("update public key must decode to exactly 32 bytes")

def validate_team_id(value):
    team = value.strip()
    if not re.fullmatch(r"[A-Za-z0-9]+", team):
        fail("installer Team ID must be ASCII alphanumeric")

def main():
    args = parse_args()
    validate_manifest_url(args.manifest_url)
    validate_public_key(args.public_key_base64)
    validate_team_id(args.installer_team_id)
    print("BLACKSTOCK_PRODUCTION_PACKAGE_CONFIG_PASS")

if __name__ == "__main__":
    main()
