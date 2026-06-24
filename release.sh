#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./release.sh [keychain-profile]
#
# Defaults to the notarytool profile saved as "MacStatNotary":
#   xcrun notarytool store-credentials "MacStatNotary" ...
#
# Environment overrides:
#   TEAM_ID=3759733MVC
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (3759733MVC)"
#
# Generates a signed, notarized MacStat.dmg in the project root.

KEYCHAIN_PROFILE="${1:-MacStatNotary}"
TEAM_ID="${TEAM_ID:-3759733MVC}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/MacStat/MacStat.xcodeproj"
WORK_DIR="${RELEASE_WORK_DIR:-/private/tmp/macstat-release}"
ARCHIVE="$WORK_DIR/MacStat.xcarchive"
EXPORT_DIR="$WORK_DIR/export"
STAGING_DIR="$WORK_DIR/dmg-staging"
APP="$EXPORT_DIR/MacStat.app"
TMP_DMG="$WORK_DIR/MacStat.dmg"
DMG="$SCRIPT_DIR/MacStat.dmg"

find_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi

  security find-identity -p codesigning -v |
    sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\".*/\1/p" |
    head -n 1
}

CODESIGN_IDENTITY="$(find_codesign_identity)"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  cat >&2 <<EOF
No Developer ID Application signing identity found for team $TEAM_ID.

Install the Developer ID Application certificate and private key in Keychain,
then verify it with:

  security find-identity -p codesigning -v | grep "Developer ID Application"

You can also override the identity explicitly:

  CODESIGN_IDENTITY="Developer ID Application: Your Name ($TEAM_ID)" ./release.sh "$KEYCHAIN_PROFILE"
EOF
  exit 1
fi

echo "==> Using signing identity: $CODESIGN_IDENTITY"
echo "==> Using notary profile: $KEYCHAIN_PROFILE"

echo "==> Cleaning build dir"
rm -rf "$WORK_DIR" "$DMG"
mkdir -p "$WORK_DIR"

echo "==> Archiving universal Release app"
xcodebuild \
  -project "$PROJECT" \
  -scheme MacStat \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

echo "==> Exporting Developer ID app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$SCRIPT_DIR/MacStat/ExportOptions.plist"

echo "==> Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Creating DMG staging folder"
mkdir -p "$STAGING_DIR"
ditto --noextattr --noacl "$APP" "$STAGING_DIR/MacStat.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG"
if command -v create-dmg &>/dev/null; then
  create-dmg \
    --volname "MacStat" \
    --window-pos 200 120 \
    --window-size 560 340 \
    --icon-size 128 \
    --icon "MacStat.app" 140 170 \
    --hide-extension "MacStat.app" \
    --app-drop-link 420 170 \
    "$TMP_DMG" \
    "$STAGING_DIR/"
else
  hdiutil create \
    -volname MacStat \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$TMP_DMG"
fi

echo "==> Signing DMG"
codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$TMP_DMG"
codesign --verify --verbose=2 "$TMP_DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$TMP_DMG" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling DMG"
xcrun stapler staple "$TMP_DMG"
xcrun stapler validate "$TMP_DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$TMP_DMG"

echo "==> Verifying DMG checksum"
hdiutil verify "$TMP_DMG"

echo "==> Copying final DMG to project root"
cp -X "$TMP_DMG" "$DMG"
codesign --verify --verbose=2 "$DMG"
hdiutil verify "$DMG"

echo "==> Done: $DMG"
echo "    Canonical signed artifact: $TMP_DMG"
