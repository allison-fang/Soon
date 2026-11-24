#!/bin/bash
# Installs Soon from the latest GitHub release, replacing any copy already in
# /Applications. Running it again updates Soon.
#
#   curl -fsSL https://raw.githubusercontent.com/allison-fang/Soon/master/Scripts/install.sh | bash
#
# Downloading with curl matters: a browser marks the zip as coming from the
# internet, and macOS refuses to open an app that isn't notarized by Apple.
set -euo pipefail

URL="https://github.com/allison-fang/Soon/releases/latest/download/Soon.zip"
DEST="/Applications/Soon.app"
# The certificate every release is signed with (Scripts/release.sh checks it
# too), so a swapped download signed by anyone else is refused.
CERT_SHA1="EB229EE2F9672D93E706288563D739C710363EBB"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Soon…"
curl -fsSL "$URL" -o "$tmp/Soon.zip"
ditto -x -k "$tmp/Soon.zip" "$tmp"
codesign --verify --strict -R "=certificate leaf = H\"$CERT_SHA1\"" "$tmp/Soon.app" ||
    { echo "error: the download is damaged or wasn't signed by Soon; try again" >&2; exit 1; }

if pgrep -xq Soon; then
    echo "Quitting Soon…"
    pkill -x Soon || true
    for _ in {1..20}; do pgrep -xq Soon || break; sleep 0.25; done
    ! pgrep -xq Soon || { echo "error: Soon didn't quit; quit it from its menu and run this again" >&2; exit 1; }
fi

rm -rf "$DEST"
ditto "$tmp/Soon.app" "$DEST"
open "$DEST"

version="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString)"
echo "Installed Soon $version in /Applications."
