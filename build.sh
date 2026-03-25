#!/bin/bash
set -euo pipefail

echo "Building mdv (debug)..."
swift build

APP_BUNDLE=".build/debug/mdv.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp .build/debug/mdv "$APP_BUNDLE/Contents/MacOS/mdv"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Built: $APP_BUNDLE"
