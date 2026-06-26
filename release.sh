#!/bin/bash
# Usage:
#   ./release.sh          # auto minor bump: 1.0 -> 1.1 -> 1.2
#   ./release.sh 2.0      # explicit version (major release or any override)

set -e

PROJ="MacStat/MacStat.xcodeproj/project.pbxproj"

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

# ── package (dmg with drag-to-install Applications symlink) ─────────────────────
mkdir -p release
APP=/tmp/macstat-release/Build/Products/Release/MacStat.app
DMG="release/MacStat-$NEW.dmg"
rm -f "$DMG"

STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MacStat" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "packaged: $DMG ($(du -sh "$DMG" | cut -f1))"

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
