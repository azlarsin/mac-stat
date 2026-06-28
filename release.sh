#!/bin/bash
# Usage:
#   ./release.sh          # auto minor bump: 1.0 -> 1.1 -> 1.2
#   ./release.sh 2.0      # explicit version (major release or any override)

set -e

PROJ="MacStat/MacStat.xcodeproj/project.pbxproj"

# ── signing / notarization config ────────────────────────────────────────────
SIGN_ID="Developer ID Application: CHENG CHEN (3759733MVC)"
NOTARY_PROFILE="macstat-notary"   # set up once: xcrun notarytool store-credentials

# ── current version ────────────────────────────────────────────────────────────
CURRENT=$(grep "MARKETING_VERSION" "$PROJ" | head -1 \
          | sed 's/.*= \(.*\);/\1/' | tr -d '[:space:]')

# ── target version ─────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
    MAJOR=$(echo "$CURRENT" | cut -d. -f1)
    MINOR=$(echo "$CURRENT" | cut -d. -f2)
    NEW="$MAJOR.$((MINOR + 1))"
else
    NEW="$1"
fi

echo "current: $CURRENT  →  new: $NEW"
read -rp "continue? [y/N] " ok
[[ "$ok" =~ ^[Yy]$ ]] || exit 0

# ── guard: clean working tree ───────────────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: uncommitted changes — commit or stash first"
    exit 1
fi

# ── bump version in project file ───────────────────────────────────────────────
sed -i '' "s/MARKETING_VERSION = $CURRENT;/MARKETING_VERSION = $NEW;/g" "$PROJ"

# ── build ───────────────────────────────────────────────────────────────────────
echo "building..."
xcodebuild -project MacStat/MacStat.xcodeproj \
    -scheme MacStat \
    -configuration Release \
    -derivedDataPath /tmp/macstat-release \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)"

APP=/tmp/macstat-release/Build/Products/Release/MacStat.app

# ── guard: must be a universal (arm64 + x86_64) binary ───────────────────────────
# A previous release shipped x86_64-only, which made Apple Silicon Macs run it
# through Rosetta 2 and surface an incompatibility/"not optimized" prompt.
# Fail loudly here rather than ever ship a single-arch build again.
BIN="$APP/Contents/MacOS/MacStat"
if ! lipo -info "$BIN" 2>/dev/null | grep -q arm64 \
   || ! lipo -info "$BIN" 2>/dev/null | grep -q x86_64; then
    echo "error: binary is not universal (arm64 + x86_64):"
    lipo -info "$BIN"
    echo "check for ARCHS / EXCLUDED_ARCHS in your env: env | grep -iE 'arch|excluded'"
    exit 1
fi
echo "universal ok: $(lipo -info "$BIN" | sed 's/.*are: //')"

# ── sign with Developer ID + hardened runtime ───────────────────────────────────
# (no entitlements: app needs none, and this strips the debug-only
#  get-task-allow entitlement that would make notarization fail)
echo "signing..."
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"

# ── package (dmg with drag-to-install Applications symlink) ─────────────────────
mkdir -p release
DMG="release/MacStat-$NEW.dmg"
rm -f "$DMG"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MacStat" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "packaged: $DMG ($(du -sh "$DMG" | cut -f1))"

# ── notarize + staple ───────────────────────────────────────────────────────────
echo "notarizing (this can take a few minutes)..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -vvv -t install "$DMG" 2>&1 | head -3 || true

# ── commit + tag + push ─────────────────────────────────────────────────────────
git add "$PROJ"
git commit -m "bump version to $NEW"
git tag "v$NEW"
git push origin main
git push origin "v$NEW"

echo ""
echo "done. create GitHub Release:"
echo "  https://github.com/azlarsin/mac-stat/releases/new?tag=v$NEW"
echo "  attach: $DMG"
