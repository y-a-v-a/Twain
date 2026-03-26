#!/bin/bash
set -euo pipefail

echo "Cleaning build artifacts..."
swift package clean
rm -rf .build/debug/Twain.app .build/release/Twain.app
echo "Clean."
