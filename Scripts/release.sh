#!/bin/bash
# Builds, signs and publishes a Soon release on GitHub.
#
#   Scripts/release.sh <notes.md>
#
# The version comes from MARKETING_VERSION in the Xcode project; bump it in a PR
# before releasing. Soon isn't notarized. It's signed with a self-signed
# certificate in the releaser's login keychain, and every release must use the
# same one: macOS ties Calendar and Keychain access to it, so a new certificate
# makes an update look like a different app.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO="allison-fang/Soon"
IDENTITY="${SOON_SIGN_IDENTITY:-Soon Code Signing}"
BUILD_DIR="build/release"
DIST="dist"
APP="$DIST/Soon.app"
# Unversioned, so releases/latest/download/Soon.zip always points at the newest.
ZIP="$DIST/Soon.zip"

fail() { echo "error: $*" >&2; exit 1; }

NOTES="${1:-}"
[[ -n "$NOTES" ]] || fail "usage: Scripts/release.sh <notes.md>"
[[ -s "$NOTES" ]] || fail "no release notes at $NOTES"

[[ "$(git branch --show-current)" == "master" ]] || fail "release from master"
git diff --quiet && git diff --cached --quiet || fail "commit or discard local changes first"
git fetch -q origin master
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/master)" ]] || fail "master isn't in sync with origin/master"

security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || fail "no '$IDENTITY' certificate in the keychain.
  Keychain Access > Certificate Assistant > Create a Certificate…
  Name: $IDENTITY, Identity Type: Self-Signed Root, Certificate Type: Code Signing"

settings="$(xcodebuild -project MeetingBar.xcodeproj -scheme MeetingBar -configuration Release -showBuildSettings 2>/dev/null)"
setting() { awk -F' = ' -v key="$1" '$1 ~ "^ *"key"$" { print $2; exit }' <<<"$settings"; }

VERSION="$(setting MARKETING_VERSION)"
[[ -n "$VERSION" ]] || fail "couldn't read MARKETING_VERSION"
TAG="v$VERSION"
! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || fail "$TAG is already released; bump MARKETING_VERSION"

for key in GOOGLE_CLIENT_NUMBER GOOGLE_CLIENT_SECRET GOOGLE_AUTH_KEYCHAIN_NAME; do
    value="$(setting "$key")"
    [[ -n "$value" && "$value" != REPLACE_BY_YOUR_* ]] || fail "$key isn't set; add it to XCConfig/DevTeamOverride.xcconfig"
done

echo "Building Soon $VERSION…"
rm -rf "$BUILD_DIR" "$DIST"
mkdir -p "$DIST"
xcodebuild -project MeetingBar.xcodeproj -scheme MeetingBar -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$BUILD_DIR" \
    -clonedSourcePackagesDirPath build/SourcePackages -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    -quiet build
ditto "$BUILD_DIR/Build/Products/Release/Soon.app" "$APP"

echo "Signing with '$IDENTITY'…"
# Nested code first, then the app. No hardened runtime: it only matters for
# notarization, and its library validation refuses code from a certificate with
# no team. No entitlements either: the project's time-sensitive notification
# entitlement needs an Apple provisioning profile, and without one macOS won't
# launch the app. Notifications fall back to the normal interruption level.
while IFS= read -r -d '' nested; do
    codesign --force --sign "$IDENTITY" "$nested"
done < <(find "$APP/Contents" -depth \( -name "*.app" -o -name "*.framework" -o -name "*.dylib" -o -name "*.xpc" \) -print0)
codesign --force --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"

echo "Publishing $TAG…"
gh release create "$TAG" "$ZIP" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "Soon $VERSION" --notes-file "$NOTES"
