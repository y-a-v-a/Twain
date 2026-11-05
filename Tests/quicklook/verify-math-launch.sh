#!/bin/bash
# Launches an assembled Twain.app on a document with formulas, with the resource
# bundle in the build directory hidden, as it is on any Mac but the one that built
# the app. SwiftPM's `Bundle.module` falls back to that absolute path, so a lookup
# that only works through it passes every other check and crashes for users.
#
# Needs a GUI session, unlike verify-bundle.sh. It catches a crash on the first
# formula, not a formula that draws blank.
set -euo pipefail

APP="$(cd "${1:-.build/debug/Twain.app}" && pwd -P)"
BINARY="$APP/Contents/MacOS/Twain"
BUILT_BUNDLE="$(dirname "$APP")/swiftui-math_SwiftUIMath.bundle"
WORK="$(mktemp -d)"
WAIT_SECONDS=10

fail() { echo "verify-math-launch: $1" >&2; exit 1; }

cleanup() {
    pkill -f "^$BINARY" || true
    [ -e "$BUILT_BUNDLE.hidden" ] && mv "$BUILT_BUNDLE.hidden" "$BUILT_BUNDLE"
    rm -rf "$WORK"
}
trap cleanup EXIT

! pgrep -f "^$BINARY" >/dev/null || fail "this build of Twain is already running"
[ -d "$BUILT_BUNDLE" ] || fail "no resource bundle to hide at $BUILT_BUNDLE"
mv "$BUILT_BUNDLE" "$BUILT_BUNDLE.hidden"

printf 'Inline $x^2$ formula.\n\n$$E = mc^2$$\n' > "$WORK/math.md"
# After an earlier crash, macOS would otherwise wait on a dialog offering to reopen the
# windows, never get to the document, and let this check pass.
open -n -g --stderr "$WORK/stderr" -a "$APP" "$WORK/math.md" --args -ApplePersistenceIgnoreState YES
sleep "$WAIT_SECONDS"

if grep -a -q -E 'Fatal error|could not load resource bundle' "$WORK/stderr"; then
    grep -a -E 'Fatal error|could not load resource bundle' "$WORK/stderr" >&2
    fail "crashed on the first formula"
fi
pgrep -f "^$BINARY" >/dev/null || fail "not running ${WAIT_SECONDS}s after opening a document with formulas"

echo "verify-math-launch: OK ($APP)"
