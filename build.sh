#!/bin/bash
set -euo pipefail

RELEASE=0
RUN=0

for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=1 ;;
        --run)     RUN=1 ;;
        --clean)
            echo "Cleaning build artifacts..."
            swift package clean
            rm -rf .build/debug/Twain.app .build/release/Twain.app
            echo "Clean."
            exit 0
            ;;
        *) echo "Usage: $0 [--release] [--run] [--clean]"; exit 1 ;;
    esac
done

if [ $RELEASE -eq 1 ]; then
    CONFIG="release"
    echo "Building Twain (release)..."
    swift build -c release
else
    CONFIG="debug"
    echo "Building Twain (debug)..."
    swift build
fi

ARCH=$(uname -m | sed s/x86_64/x86_64/ | sed s/arm64/arm64/)
BUILD_DIR=".build/${ARCH}-apple-macosx/${CONFIG}"

APP_BUNDLE=".build/$CONFIG/Twain.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
# Remove before copying: overwriting the executable in place reuses its inode, and once
# the old binary has been launched, the kernel's cached signature for that inode kills
# the next launch with "Taskgated Invalid Signature" (launchd spawn error 162).
rm -f "$APP_BUNDLE/Contents/MacOS/Twain"
cp ".build/$CONFIG/Twain" "$APP_BUNDLE/Contents/MacOS/Twain"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Twain.icns "$APP_BUNDLE/Contents/Resources/Twain.icns"
cp Twain.sdef "$APP_BUNDLE/Contents/Resources/Twain.sdef"
# Copy SPM resource bundles so Textual can load Prism.js for syntax highlighting
rm -rf "$APP_BUNDLE/Contents/Resources/"*.bundle
for bundle in "$BUILD_DIR"/*.bundle; do
    cp -r "$bundle" "$APP_BUNDLE/Contents/Resources/"
done

# Quick Look preview extension: hand-assembled appex (SPM can't build .appex
# targets). The binary's entry point is NSExtensionMain, set at link time in
# Package.swift. Signed before the outer app, sandboxed via entitlements —
# unsandboxed app extensions are not loaded.
APPEX="$APP_BUNDLE/Contents/PlugIns/TwainQuickLook.appex"
rm -rf "$APPEX"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp "$BUILD_DIR/TwainQuickLook" "$APPEX/Contents/MacOS/TwainQuickLook"
cp quicklook/Info.plist "$APPEX/Contents/Info.plist"
# The appex is its own main bundle, so it needs its own copy of the SPM
# resource bundles (Prism.js for code highlighting).
for bundle in "$BUILD_DIR"/*.bundle; do
    cp -r "$bundle" "$APPEX/Contents/Resources/"
done
codesign --force --sign - --entitlements quicklook/TwainQuickLook.entitlements "$APPEX" 2>/dev/null || true

# Re-sign the assembled bundle so the fresh binary and resources carry a consistent
# ad-hoc signature. Must come after the appex is signed: adding PlugIns content
# invalidates the outer seal.
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Built: $APP_BUNDLE"

if [ $RUN -eq 1 ]; then
    echo "Opening Twain..."
    open -a "$(pwd)/$APP_BUNDLE" test.md
fi
