#!/bin/bash
set -euo pipefail

echo "Cleaning build artifacts..."
swift package clean
rm -rf .build/debug/mdv.app .build/release/mdv.app
echo "Clean."
