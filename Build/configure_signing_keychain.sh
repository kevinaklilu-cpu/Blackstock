#!/usr/bin/env bash
set -euo pipefail

KEYCHAIN="${BLACKSTOCK_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "Signing-Keychain nicht gefunden: $KEYCHAIN" >&2
  exit 1
fi

if [[ -n "${BLACKSTOCK_SIGNING_KEYCHAIN_PASSWORD:-}" ]]; then
  KEYCHAIN_PASSWORD="$BLACKSTOCK_SIGNING_KEYCHAIN_PASSWORD"
else
  printf "macOS-Keychain-Passwort einmalig eingeben: " >&2
  IFS= read -r -s KEYCHAIN_PASSWORD
  printf "\n" >&2
fi

if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
  echo "Leeres Keychain-Passwort wird nicht akzeptiert." >&2
  exit 1
fi

security unlock-keychain   -p "$KEYCHAIN_PASSWORD"   "$KEYCHAIN"

# Keep the user's login keychain usable for the full login session.
# The keychain still locks on logout according to macOS session semantics.
security set-keychain-settings   -u   "$KEYCHAIN"

# Allow Apple's signing tools to use signing private keys without asking for
# the login password on every codesign/productbuild invocation.
security set-key-partition-list   -S apple-tool:,apple:,codesign:   -s   -k "$KEYCHAIN_PASSWORD"   "$KEYCHAIN"

security find-identity   -v   -p codesigning   "$KEYCHAIN"

cat <<EOF
Blackstock-Signing-Keychain ist konfiguriert.

Für lokale Builds in dieser Shell:
  export BLACKSTOCK_SIGNING_KEYCHAIN="$KEYCHAIN"

Danach verwendet Build/package.sh diesen Keychain explizit und sollte nicht
bei jedem codesign-Schritt erneut nach dem macOS-Passwort fragen.
EOF
