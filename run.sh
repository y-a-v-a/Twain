#!/bin/bash
set -euo pipefail

./build.sh
echo "Opening Twain..."
open .build/debug/Twain.app "$@"
