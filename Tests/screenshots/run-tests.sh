#!/bin/bash
# Visual regression checks for Twain, driven by window screenshots. macOS only:
#
#   Tests/screenshots/run-tests.sh
#
# Builds the app, renders a fixture at two different theme contentInsets under
# an isolated $HOME, captures the window with screencapture, and measures the
# actual left padding in the pixels. Catches "theme value silently has no
# visual effect" regressions that unit tests can't see.
#
# Requirements:
#   - Screen Recording permission for your terminal (screencapture)
#   - jq
#
# Set TWAIN_SCREENSHOT_DIR to keep the captured PNGs for eyeballing;
# otherwise they live in a temp dir that is removed on exit.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

if [ "$(uname)" != "Darwin" ]; then
    echo "SKIP: screenshot tests require macOS" >&2
    exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is required" >&2; exit 0; }

# A running Twain would make window targeting ambiguous and could hold the
# user's real theme; bail rather than kill it.
if pgrep -f "Twain.app/Contents/MacOS/Twain" >/dev/null; then
    echo "SKIP: Twain is already running; quit it first" >&2
    exit 0
fi

./build.sh
APP="$REPO_ROOT/.build/debug/Twain.app"

WORK=$(mktemp -d /tmp/twain-screenshots-XXXXXX)
trap 'rm -rf "$WORK"' EXIT
OUT="${TWAIN_SCREENSHOT_DIR:-$WORK/shots}"
mkdir -p "$OUT"

# Isolated config: TWAIN_CONFIG_DIR points the app away from the user's real
# ~/.config/twain, so their theme is never touched.
CONFIG_DIR="$WORK/config"
THEME="$CONFIG_DIR/theme.json"
mkdir -p "$CONFIG_DIR"

FIXTURE="$WORK/fixture.md"
cat > "$FIXTURE" <<'EOF'
# Screenshot Fixture

Enough prose to put ink on several lines, so the inset measurement finds
text at the left edge regardless of where the line wraps fall. The quick
brown steamboat rounds the bend ahead of the slow gray raft.

- one steamboat
- two steamboats
- three steamboats
EOF

PASS=0
FAIL=0

ok() {
    echo "ok - $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL - $1"
    shift
    for line in "$@"; do echo "  $line"; done
    FAIL=$((FAIL + 1))
}

# The app must be launched through `open` — DocumentGroup only opens files
# delivered via LaunchServices, not argv. `--env` carries the config override.
launch() {
    open -g -a "$APP" --env TWAIN_CONFIG_DIR="$CONFIG_DIR" "$FIXTURE"
    sleep 3
}

quit_app() {
    pkill -f "Twain.app/Contents/MacOS/Twain" || true
    sleep 1
}

# Launch the app once so it seeds a complete theme.json we can then edit.
launch
quit_app

if [ -f "$THEME" ]; then
    ok "app seeds theme.json in an isolated TWAIN_CONFIG_DIR"
else
    fail "app seeds theme.json in an isolated TWAIN_CONFIG_DIR" "no file at $THEME"
    echo "# cannot continue without a theme file"
    exit 1
fi

# Render the fixture at a given contentInset and capture the window.
capture() {
    local inset=$1 out=$2
    jq --argjson v "$inset" '.layout.contentInset = $v' "$THEME" > "$THEME.tmp"
    mv "$THEME.tmp" "$THEME"

    launch

    local pid wid
    pid=$(pgrep -f "Twain.app/Contents/MacOS/Twain" | head -1) || pid=""
    wid=""
    if [ -n "$pid" ]; then
        wid=$(swift Tests/screenshots/window-id.swift "$pid") || wid=""
    fi
    if [ -n "$wid" ]; then
        screencapture -x -o -l "$wid" "$out" || true
    fi

    quit_app

    [ -s "$out" ]
}

if capture 8 "$OUT/inset-8.png" && capture 96 "$OUT/inset-96.png"; then
    ok "captured window screenshots at contentInset 8 and 96"
else
    fail "captured window screenshots at contentInset 8 and 96" \
        "screencapture produced no image (Screen Recording permission?)"
    echo "# cannot continue without screenshots"
    exit 1
fi

SMALL=$(swift Tests/screenshots/measure-inset.swift "$OUT/inset-8.png")
LARGE=$(swift Tests/screenshots/measure-inset.swift "$OUT/inset-96.png")
echo "# measured left inset: ${SMALL}px at contentInset 8, ${LARGE}px at contentInset 96"

# 88pt of extra inset is at least 88px even at 1x scale; allow generous slack
# for antialiasing while staying far above noise.
if [ "$((LARGE - SMALL))" -ge 70 ]; then
    ok "contentInset visibly widens the content padding"
else
    fail "contentInset visibly widens the content padding" \
        "expected inset-96 to measure >=70px wider than inset-8" \
        "screenshots kept in: $OUT"
    TWAIN_SCREENSHOT_DIR_KEEP=1
fi

if [ -n "${TWAIN_SCREENSHOT_DIR:-}" ] || [ -n "${TWAIN_SCREENSHOT_DIR_KEEP:-}" ]; then
    # Keep artifacts: move them out of the temp dir before the EXIT trap.
    KEEP="${TWAIN_SCREENSHOT_DIR:-/tmp/twain-screenshots-failed}"
    if [ "$KEEP" != "$OUT" ]; then
        mkdir -p "$KEEP"
        cp "$OUT"/*.png "$KEEP"/ 2>/dev/null || true
        echo "# screenshots: $KEEP"
    fi
fi

echo "# $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
