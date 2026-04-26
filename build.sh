#!/bin/bash
# Build EdgePad.app using Swift Package Manager + custom .app wrapping.
#
# Usage:
#   ./build.sh        → build + wrap into build/EdgePad.app
#   ./build.sh run    → build + wrap + launch (background, no logs)
#   ./build.sh dev    → build + wrap + launch in foreground with live logs
#                       (kills any running EdgePad first)
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

echo "▸ Building release binary…"
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

CERT_NAME="EdgePad Local Dev"
if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
    echo "▸ Signing with '$CERT_NAME'…"
    codesign --force --deep --sign "$CERT_NAME" "$APP_BUNDLE"
else
    echo "▸ Ad-hoc signing… (run scripts/codesign/setup_local.sh once for stable signing)"
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "✓ Built $APP_BUNDLE"
echo ""
echo "  First run: grant Accessibility permission in"
echo "  System Settings → Privacy & Security → Accessibility"
echo ""

if [ "${1:-}" = "run" ]; then
    echo "▸ Launching…"
    open "$APP_BUNDLE"
fi

if [ "${1:-}" = "dev" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    echo "▸ Launching in foreground (Ctrl-C to stop)…"
    exec "$MACOS/$APP_NAME"
fi
