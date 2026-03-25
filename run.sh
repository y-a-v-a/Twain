#!/bin/bash
set -euo pipefail

./build.sh
echo "Opening mdv..."
open .build/debug/mdv.app "$@"
