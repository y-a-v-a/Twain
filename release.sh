#!/bin/bash
set -euo pipefail

echo "Building mdv (release)..."
swift build -c release

APP_BUNDLE=".build/release/mdv.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp .build/release/mdv "$APP_BUNDLE/Contents/MacOS/mdv"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built: $APP_BUNDLE"
