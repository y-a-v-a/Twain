#!/bin/bash
set -euo pipefail

echo "Building Twain (release)..."
swift build -c release

APP_BUNDLE=".build/release/Twain.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp .build/release/Twain "$APP_BUNDLE/Contents/MacOS/Twain"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built: $APP_BUNDLE"
