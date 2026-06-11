#!/bin/bash
# End-to-end checks for Twain's AppleScript support. macOS only — run locally:
#
#   Tests/applescript/run-tests.sh
#
# Builds the app, opens a fixture document, and drives it with osascript.
# The first run may show an Automation permission prompt (your terminal app
# asking to control Twain); approve it and re-run if the first attempt fails
# with error -1743.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

if [ "$(uname)" != "Darwin" ]; then
    echo "SKIP: AppleScript tests require macOS" >&2
    exit 0
fi

./build.sh
APP="$REPO_ROOT/.build/debug/Twain.app"

FIXTURE_BASE=$(mktemp /tmp/twain-applescript-XXXXXX)
FIXTURE="$FIXTURE_BASE.md"
mv "$FIXTURE_BASE" "$FIXTURE"
trap 'rm -f "$FIXTURE"' EXIT
cat > "$FIXTURE" <<'EOF'
# AppleScript Fixture

A unique marker: XYZZY-ORIGINAL.
EOF

DOC_NAME=$(basename "$FIXTURE")

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

twain_tell() {
    osascript -e "tell application \"Twain\" to $1"
}

open -g -a "$APP" "$FIXTURE"
sleep 2

# --- Introspection -------------------------------------------------------

COUNT=$(twain_tell 'count documents')
if [ "$COUNT" -ge 1 ]; then
    ok "count documents >= 1 (got $COUNT)"
else
    fail "count documents >= 1" "got: $COUNT"
fi

NAME=$(twain_tell "get name of document \"$DOC_NAME\"")
if [ "$NAME" = "$DOC_NAME" ]; then
    ok "document is addressable by name"
else
    fail "document is addressable by name" "got: $NAME"
fi

DOC_PATH=$(twain_tell "get path of document \"$DOC_NAME\"")
case "$DOC_PATH" in
    /*"$DOC_NAME") ok "path is absolute and ends in the file name ($DOC_PATH)" ;;
    *) fail "path is absolute and ends in the file name" "got: $DOC_PATH" ;;
esac

SRC=$(twain_tell "get source text of document \"$DOC_NAME\"")
case "$SRC" in
    "# AppleScript Fixture"*XYZZY-ORIGINAL*) ok "source text is the raw markdown" ;;
    *) fail "source text is the raw markdown" "got: $SRC" ;;
esac

RENDERED=$(twain_tell "get rendered text of document \"$DOC_NAME\"")
case "$RENDERED" in
    "#"*) fail "rendered text is parsed (no leading #)" "got: $RENDERED" ;;
    *XYZZY-ORIGINAL*) ok "rendered text is parsed plain text with the content" ;;
    *) fail "rendered text contains the content" "got: $RENDERED" ;;
esac

# --- Commands ------------------------------------------------------------

if twain_tell "search document \"$DOC_NAME\" for \"marker\"" >/dev/null; then
    ok "search command is accepted"
else
    fail "search command is accepted"
fi

if twain_tell "search document \"$DOC_NAME\"" >/dev/null 2>&1; then
    fail "search without a query is rejected"
else
    ok "search without a query is rejected"
fi

sed -i '' 's/XYZZY-ORIGINAL/XYZZY-UPDATED/' "$FIXTURE"
twain_tell "refresh document \"$DOC_NAME\"" >/dev/null
sleep 1
SRC=$(twain_tell "get source text of document \"$DOC_NAME\"")
case "$SRC" in
    *XYZZY-UPDATED*) ok "refresh picks up the change on disk" ;;
    *) fail "refresh picks up the change on disk" "got: $SRC" ;;
esac

BEFORE=$(twain_tell 'count documents')
twain_tell "close document \"$DOC_NAME\"" >/dev/null
sleep 1
AFTER=$(twain_tell 'count documents')
if [ "$AFTER" -lt "$BEFORE" ]; then
    ok "close removes the document ($BEFORE -> $AFTER)"
else
    fail "close removes the document" "before=$BEFORE after=$AFTER"
fi

# --- Summary --------------------------------------------------------------

echo
echo "$PASS passed, $FAIL failed"
echo "(Twain is left running; quit with: osascript -e 'tell application \"Twain\" to quit')"
[ "$FAIL" -eq 0 ]
