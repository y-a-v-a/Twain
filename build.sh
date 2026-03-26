#!/bin/bash
set -euo pipefail

echo "Building Twain (debug)..."
swift build

APP_BUNDLE=".build/debug/Twain.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp .build/debug/Twain "$APP_BUNDLE/Contents/MacOS/Twain"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built: $APP_BUNDLE"
