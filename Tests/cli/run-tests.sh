#!/bin/bash
# Tests for the `twain` CLI embedded in install.sh.
#
# Self-contained: extracts the CLI from install.sh, stubs `open` to record its
# invocations, and asserts on the commands the CLI would run. Needs no Twain.app
# and no macOS — it runs on Linux too, so it doubles as a cheap CI check.
#
#   Tests/cli/run-tests.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Harness -----------------------------------------------------------------

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
    sed 's/^/  log: /' "$WORK/open.log" 2>/dev/null || true
    FAIL=$((FAIL + 1))
}

run_cli() {
    : > "$WORK/open.log"
    "$WORK/twain" "$@"
}

# Assert the open log contains a line including the given substring.
assert_log_contains() {
    local desc="$1" expected="$2"
    if grep -qF -- "$expected" "$WORK/open.log"; then
        ok "$desc"
    else
        fail "$desc" "expected log to contain: $expected"
    fi
}

# Assert the open log contains this exact line.
assert_log_line() {
    local desc="$1" expected="$2"
    if grep -qxF -- "$expected" "$WORK/open.log"; then
        ok "$desc"
    else
        fail "$desc" "expected log line: $expected"
    fi
}

assert_log_line_count() {
    local desc="$1" expected="$2"
    local actual
    actual=$(wc -l < "$WORK/open.log" | tr -d ' ')
    if [ "$actual" -eq "$expected" ]; then
        ok "$desc"
    else
        fail "$desc" "expected $expected open call(s), got $actual"
    fi
}

# --- Setup -------------------------------------------------------------------

sed -n "/^cat > \"\$TMPFILE\" << 'SCRIPT'\$/,/^SCRIPT\$/p" "$REPO_ROOT/install.sh" \
    | sed '1d;$d' > "$WORK/twain"
chmod +x "$WORK/twain"
if [ ! -s "$WORK/twain" ]; then
    echo "FATAL: could not extract the CLI from install.sh" >&2
    exit 1
fi

mkdir -p "$WORK/bin"
cat > "$WORK/bin/open" <<EOF
#!/bin/bash
echo "OPEN: \$*" >> "$WORK/open.log"
EOF
chmod +x "$WORK/bin/open"
export PATH="$WORK/bin:$PATH"

mkdir -p "$WORK/docs"
printf '# hi\n' > "$WORK/docs/a.md"
printf '# hi\n' > "$WORK/docs/b.md"
printf '# hi\n' > "$WORK/docs/release notes.md"

cd "$WORK"

# --- Opening files -----------------------------------------------------------

run_cli docs/a.md
assert_log_line "opens a file with an absolute path" \
    "OPEN: -a Twain $WORK/docs/a.md"

run_cli docs/a.md docs/b.md
assert_log_line_count "opens each listed file" 2

run_cli -g "docs/release notes.md"
assert_log_line "background open passes -g and handles spaces in paths" \
    "OPEN: -g -a Twain $WORK/docs/release notes.md"

run_cli
assert_log_line "no arguments just opens the app" "OPEN: -a Twain"

# --- Find --------------------------------------------------------------------

run_cli --find "Phase 2 & más" docs/a.md
assert_log_contains "find+file goes through twain://open" \
    "twain://open?file=$WORK/docs/a.md"
assert_log_contains "find query is percent-encoded byte-wise (UTF-8, &, space)" \
    "search=Phase%202%20%26%20m%C3%A1s"
assert_log_line "app is launched before the URL is sent" "OPEN: -g -a Twain"

run_cli -g --find hello docs/a.md
assert_log_contains "background find adds activate=0" "&activate=0"
assert_log_contains "background find opens the URL with -g" \
    "OPEN: -g twain://open?file="

run_cli --find "loose query"
assert_log_line "find without files searches open documents" \
    "OPEN: twain://search?q=loose%20query"

# --- Refresh -----------------------------------------------------------------

run_cli --refresh
assert_log_line "bare refresh broadcasts" "OPEN: -g twain://refresh"

run_cli --refresh docs/a.md
assert_log_line "refresh with a file targets it" \
    "OPEN: -g twain://refresh?file=$WORK/docs/a.md"

# --- Stdin -------------------------------------------------------------------

printf '# from stdin\n' | run_cli -
STDIN_FILE=$(sed -n 's/^OPEN: -a Twain //p' "$WORK/open.log")
case "$STDIN_FILE" in
    *.md) ok "stdin lands in a .md temp file" ;;
    *)    fail "stdin lands in a .md temp file" "opened: $STDIN_FILE" ;;
esac
if [ -n "$STDIN_FILE" ] && [ "$(cat "$STDIN_FILE")" = "# from stdin" ]; then
    ok "stdin content is written to the temp file"
else
    fail "stdin content is written to the temp file" "file: $STDIN_FILE"
fi
rm -f "$STDIN_FILE"

# --- Errors ------------------------------------------------------------------

: > "$WORK/open.log"
if "$WORK/twain" missing.md 2>/dev/null; then
    fail "missing file exits non-zero"
else
    ok "missing file exits non-zero"
fi
assert_log_line_count "missing file opens nothing" 0

if "$WORK/twain" --bogus >/dev/null 2>&1; then
    fail "unknown option exits non-zero"
else
    ok "unknown option exits non-zero"
fi

if "$WORK/twain" --find >/dev/null 2>&1; then
    fail "--find without an argument exits non-zero"
else
    ok "--find without an argument exits non-zero"
fi

# --- Summary -----------------------------------------------------------------

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
