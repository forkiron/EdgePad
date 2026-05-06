#!/bin/bash
# EdgePad one-line installer.
#
# Usage (from a user's terminal):
#   curl -fsSL https://raw.githubusercontent.com/forkiron/EdgePad/main/install.sh | bash
#
# Why this exists: macOS attaches a quarantine flag (com.apple.quarantine) to
# anything downloaded by a web browser, which is what triggers Gatekeeper's
# "unidentified developer" warning. curl/wget/git don't set that flag, so an
# app fetched this way runs without prompting. Same binary, same signing
# status — just no quarantine bit, so no Gatekeeper interception.

set -euo pipefail

REPO="forkiron/EdgePad"
APP_NAME="EdgePad"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[0;34m%s\033[0m\n" "$*"; }

trap 'red "✗ Install failed. Re-run or grab the .zip directly from https://github.com/${REPO}/releases/latest"' ERR

if [ "$(uname)" != "Darwin" ]; then
    red "✗ EdgePad is macOS-only."
    exit 1
fi

blue "▸ Looking up latest EdgePad release…"
ZIP_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -o 'https://[^"]*EdgePad-[^"]*\.zip' \
    | head -1)

if [ -z "$ZIP_URL" ]; then
    red "✗ Could not find a .zip asset on the latest release."
    exit 1
fi

VERSION=$(printf '%s' "$ZIP_URL" | sed -n 's/.*EdgePad-\(.*\)\.zip/\1/p')
blue "▸ Found EdgePad ${VERSION}"

TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

blue "▸ Downloading…"
curl -fsSL "$ZIP_URL" -o "${TMP}/EdgePad.zip"

blue "▸ Unzipping…"
unzip -q -o "${TMP}/EdgePad.zip" -d "$TMP"

if [ ! -d "${TMP}/${APP_BUNDLE}" ]; then
    red "✗ Zip didn't contain ${APP_BUNDLE}."
    exit 1
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    blue "▸ Quitting running EdgePad…"
    osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || pkill -x "$APP_NAME" || true
    sleep 1
fi

if [ ! -w "$INSTALL_DIR" ]; then
    red "✗ ${INSTALL_DIR} is not writable. Re-run with sudo, or set INSTALL_DIR=~/Applications and re-run."
    exit 1
fi

blue "▸ Installing to ${INSTALL_DIR}/${APP_BUNDLE}…"
rm -rf "${INSTALL_DIR:?}/${APP_BUNDLE}"
mv "${TMP}/${APP_BUNDLE}" "${INSTALL_DIR}/"

# Belt-and-suspenders: if anything in the chain ever did set a quarantine
# attribute, drop it now so launch is silent.
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_BUNDLE}" 2>/dev/null || true

blue "▸ Launching…"
open "${INSTALL_DIR}/${APP_BUNDLE}"

echo
green "✓ EdgePad ${VERSION} installed."
echo "  Grant Accessibility permission when prompted:"
echo "  System Settings → Privacy & Security → Accessibility"
