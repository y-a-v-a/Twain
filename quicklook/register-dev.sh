#!/bin/bash
# Register the Quick Look extension from a local dev build with pluginkit and
# elect it for Markdown previews. Only needed for builds run out of .build —
# the installed app registers automatically when launched from ~/Applications.
#
# Undo with: pluginkit -r <path printed below>
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
APPEX="$(pwd)/.build/$CONFIG/Twain.app/Contents/PlugIns/TwainQuickLook.appex"

[ -d "$APPEX" ] || { echo "register-dev.sh: no appex at $APPEX (run ./build.sh first)" >&2; exit 1; }

pluginkit -a "$APPEX"
pluginkit -e use -i io.vincentb.twain.quicklook
pluginkit -m -v -p com.apple.quicklook.preview | grep -i twain
echo "Registered. Test with: qlmanage -p test.md"
