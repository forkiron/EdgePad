#!/bin/bash
# Package EdgePad into a distributable EdgePad-<version>.zip.
#
# Usage:
#   ./package.sh         → reads version from Info.plist (CFBundleShortVersionString)
#   ./package.sh 0.2.0   → override version label on the zip filename
#
# Output: build/EdgePad-<version>.zip
#
# Note: the .app inside is ad-hoc signed. On first launch, users will see
# Gatekeeper's "unidentified developer" prompt — they need to right-click
# the .app and choose Open. That goes away once you sign + notarize with a
# paid Apple Developer ID.

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="EdgePad"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
fi

ZIP_NAME="$APP_NAME-$VERSION.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

echo "▸ Building ${APP_NAME} ${VERSION}…"
./build.sh

if [ ! -d "$APP_BUNDLE" ]; then
    echo "✗ build.sh did not produce $APP_BUNDLE"
    exit 1
fi

echo "▸ Stripping quarantine + extended attrs…"
xattr -cr "$APP_BUNDLE"

echo "▸ Zipping → $ZIP_PATH"
rm -f "$ZIP_PATH"
# ditto preserves macOS metadata + symlinks correctly; plain `zip` can corrupt
# the bundle's signature on some hosts.
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo ""
echo "✓ $ZIP_PATH ($SIZE)"
echo ""
echo "  Upload this to GitHub Releases / your landing page."
echo "  First-launch instructions to put on the page:"
echo "    1. Unzip → drag EdgePad.app to /Applications"
echo "    2. Right-click EdgePad.app → Open (one-time Gatekeeper prompt)"
echo "    3. Grant Accessibility permission when asked"
