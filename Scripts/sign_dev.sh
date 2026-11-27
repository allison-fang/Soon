#!/bin/bash
# Signs a local SoonDev.app with the release certificate.
#
#   Scripts/sign_dev.sh build/DerivedData/Build/Products/Debug/SoonDev.app
#
# Unsigned debug builds carry only the linker's signature, which changes on
# every build and doesn't bind the bundle ID. macOS can't match a Calendar
# grant to it, so SoonDev loses access after each rebuild while System Settings
# still shows it on. A certificate signature stays the same across builds.
# Signed like Scripts/release.sh: no hardened runtime and no entitlements.
set -euo pipefail

APP="${1:?usage: Scripts/sign_dev.sh <path to SoonDev.app>}"
IDENTITY="${SOON_SIGN_IDENTITY:-Soon Code Signing}"

[[ -d "$APP" ]] || { echo "error: no app at $APP" >&2; exit 1; }
if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "warning: no '$IDENTITY' certificate; SoonDev will need Calendar access again after each build" >&2
    exit 0
fi

while IFS= read -r -d '' nested; do
    codesign --force --sign "$IDENTITY" "$nested" 2>/dev/null
done < <(find "$APP/Contents" -depth \( -name "*.app" -o -name "*.framework" -o -name "*.dylib" -o -name "*.xpc" -o -name "*.appex" -o -name "*.xctest" \) -print0)
codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null
