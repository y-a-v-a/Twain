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
cp ".build/$CONFIG/Twain" "$APP_BUNDLE/Contents/MacOS/Twain"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Twain.icns "$APP_BUNDLE/Contents/Resources/Twain.icns"
# Copy SPM resource bundles so Textual can load Prism.js for syntax highlighting
rm -rf "$APP_BUNDLE/Contents/Resources/"*.bundle
for bundle in "$BUILD_DIR"/*.bundle; do
    cp -r "$bundle" "$APP_BUNDLE/Contents/Resources/"
done

echo "Built: $APP_BUNDLE"

if [ $RUN -eq 1 ]; then
    echo "Opening Twain..."
    open "$APP_BUNDLE"
fi
