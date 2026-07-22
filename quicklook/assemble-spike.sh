#!/bin/bash
# Quick Look spike: assemble the TwainQuickLook appex into the built Twain.app,
# register it with pluginkit, and print verification steps. Debug build only —
# this script is throwaway spike tooling.
set -euo pipefail

cd "$(dirname "$0")/.."

./build.sh

ARCH=$(uname -m)
BUILD_DIR=".build/${ARCH}-apple-macosx/debug"
APP_BUNDLE="$(pwd)/.build/debug/Twain.app"
APPEX="$APP_BUNDLE/Contents/PlugIns/TwainQuickLook.appex"

swift build --product TwainQuickLook

# Same inode-reuse gotcha as build.sh: remove before copying.
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS"
cp "$BUILD_DIR/TwainQuickLook" "$APPEX/Contents/MacOS/TwainQuickLook"
cp quicklook/Info.plist "$APPEX/Contents/Info.plist"

# Sign inside-out: the appex (sandboxed, with entitlements) first, then the
# outer app whose seal the new PlugIns content just invalidated.
codesign --force --sign - --entitlements quicklook/TwainQuickLook.entitlements "$APPEX"
codesign --force --sign - "$APP_BUNDLE"

echo "--- registering with pluginkit"
pluginkit -a "$APPEX"
pluginkit -e use -i io.vincentb.twain.quicklook || true

echo "--- discovery check"
pluginkit -m -v -p com.apple.quicklook.preview | grep -i twain || {
    echo "NOT REGISTERED"; exit 1;
}

echo
echo "OK. Now test interactively:  qlmanage -p test.md"
echo "(or select test.md in Finder and press space)"
