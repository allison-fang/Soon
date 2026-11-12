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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Soon…"
curl -fsSL "$URL" -o "$tmp/Soon.zip"
ditto -x -k "$tmp/Soon.zip" "$tmp"
codesign --verify --strict "$tmp/Soon.app" || { echo "error: the download is damaged; try again" >&2; exit 1; }

if pgrep -xq Soon; then
    echo "Quitting Soon…"
    pkill -x Soon || true
    for _ in {1..20}; do pgrep -xq Soon || break; sleep 0.25; done
fi

rm -rf "$DEST"
ditto "$tmp/Soon.app" "$DEST"
open "$DEST"

version="$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString)"
echo "Installed Soon $version in /Applications."
