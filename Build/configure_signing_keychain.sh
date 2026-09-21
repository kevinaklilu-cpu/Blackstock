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

security unlock-keychain \
  -p "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN"

# Keep the explicitly configured signing keychain available for the active
# development session. This avoids repeated unlock prompts between codesign,
# pkgbuild/productbuild and subsequent local rebuilds. It does not disable
# the user's normal login-keychain protections.
security set-keychain-settings \
  -lut 86400 \
  "$KEYCHAIN"

# Allow Apple's signing tools to use signing private keys without asking for
# the login password on every codesign/productbuild invocation.
security set-key-partition-list   -S apple-tool:,apple:,codesign:   -s   -k "$KEYCHAIN_PASSWORD"   "$KEYCHAIN"

security find-identity \
  -v \
  -p codesigning \
  "$KEYCHAIN"

# Verify non-interactively that the signing material can actually be read
# now. A failure here is preferable to several password prompts later.
security find-identity \
  -v \
  -p codesigning \
  "$KEYCHAIN" >/dev/null

cat <<EOF
Blackstock-Signing-Keychain ist konfiguriert.

Für lokale Builds in dieser Shell:
  export BLACKSTOCK_SIGNING_KEYCHAIN="$KEYCHAIN"

Danach verwendet Build/package.sh diesen Keychain explizit. Für die aktuelle
Arbeitssitzung sollte macOS nicht bei jedem codesign-/productbuild-Schritt
erneut nach dem Passwort fragen. Nach Neustart/Logout oder wenn du den
Schlüsselbund selbst sperrst, kann eine erneute einmalige Freigabe nötig sein.
EOF
