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
FRAMEWORKS="$CONTENTS/Frameworks"
mkdir -p "$MACOS" "$RES" "$FRAMEWORKS"

cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

cp Resources/Info.plist "$CONTENTS/Info.plist"

echo "▸ Embedding OpenMultitouchSupportXCF.framework…"
# SPM extracts the right architecture slice here during build.
OMS_SRC=""
for candidate in \
    ".build/arm64-apple-macosx/release/OpenMultitouchSupportXCF.framework" \
    ".build/x86_64-apple-macosx/release/OpenMultitouchSupportXCF.framework" \
    ".build/release/OpenMultitouchSupportXCF.framework"
do
    if [ -d "$candidate" ]; then
        OMS_SRC="$candidate"
        break
    fi
done
if [ -z "$OMS_SRC" ]; then
    echo "✗ Could not locate OpenMultitouchSupportXCF.framework under .build/"
    find .build -name "OpenMultitouchSupportXCF.framework" -type d 2>/dev/null || true
    exit 1
fi
cp -R "$OMS_SRC" "$FRAMEWORKS/"

echo "▸ Patching rpath so the binary can find embedded frameworks…"
# The SPM-built binary links with @rpath/… install names but has no
# rpath that resolves inside a .app bundle. Add one that points at
# Contents/Frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true

echo "▸ Ad-hoc signing (replace with Developer ID for distribution)…"
# Sign the embedded framework first (inside-out), then the app.
codesign --force --sign - "$FRAMEWORKS/OpenMultitouchSupportXCF.framework"
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
