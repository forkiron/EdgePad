#!/bin/bash
# Build EdgePad.app using Swift Package Manager + custom .app wrapping.
#
# Usage:
#   ./build.sh        → build + wrap into build/EdgePad.app
#   ./build.sh run    → build + wrap + launch
#   ./build.sh clean  → remove build artifacts

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="EdgePad"
BUNDLE_ID="com.thomaslenh.EdgePad"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

if [ "${1:-}" = "clean" ]; then
    echo "▸ Cleaning…"
    rm -rf "$BUILD_DIR" .build
    echo "✓ Clean."
    exit 0
fi

echo "▸ Resolving SwiftPM dependencies…"
swift package resolve

echo "▸ Building release binary (this fetches OpenMultitouchSupport on first run)…"
swift build -c release

# swift build places the binary at .build/release/$APP_NAME
BINARY=".build/release/$APP_NAME"
if [ ! -x "$BINARY" ]; then
    # Apple Silicon path alternative
    BINARY=".build/arm64-apple-macosx/release/$APP_NAME"
fi
if [ ! -x "$BINARY" ]; then
    echo "✗ Could not find built binary at .build/release/$APP_NAME"
    ls -la .build/release/ 2>/dev/null || true
    exit 1
fi

echo "▸ Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RES"

cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✓ Built $APP_BUNDLE"
echo ""
echo "  First run: grant Accessibility permission in"
echo "  System Settings → Privacy & Security → Accessibility"
echo ""

if [ "${1:-}" = "run" ]; then
    echo "▸ Launching…"
    open "$APP_BUNDLE"
fi
