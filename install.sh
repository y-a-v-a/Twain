#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install.sh [-h|--help]

Builds and installs Twain, the Markdown viewer:

  1. Builds a RELEASE build via ./build.sh --release
     (never the debug build in .build/debug — use build.sh for dev builds)
  2. Installs the app bundle to ~/Applications/Twain.app,
     replacing any existing copy
  3. Installs the `twain` CLI to ~/.bin/twain

Note: the installed app reads the live ~/.config/twain/theme.json;
installing does not touch or reset it.
EOF
}

case "${1:-}" in
    "") ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 1 ;;
esac

./build.sh --release

APP_SOURCE=".build/release/Twain.app"
APP_DEST="$HOME/Applications/Twain.app"
CLI_DEST="$HOME/.bin/twain"

mkdir -p "$HOME/Applications"
echo "Installing Twain.app to ~/Applications..."
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

TMPFILE=$(mktemp)
cat > "$TMPFILE" << 'SCRIPT'
#!/bin/bash
# twain — CLI for the Twain Markdown viewer.
# Plain file opens go through `open -a <installed app>`; everything else is
# driven over the twain:// URL scheme so it also works on an already-running
# instance.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: twain [options] [file ...]
       command | twain -

Opens Markdown files in Twain. With no arguments, opens the app.

Options:
  -g, --background    Open without bringing Twain to the foreground
  -f, --find <text>   Open search with <text> and jump to the first match.
                      With files: opens them searching for <text>.
                      Without files: searches all open documents.
  -r, --refresh       Ask Twain to re-read documents from disk (all open
                      documents, or only the listed files)
  -                   Read Markdown from stdin and open it
      --version       Print the installed Twain version
  -h, --help          Show this help

Examples:
  twain README.md                   # open a file
  twain -g report.md                # open without stealing focus
  twain --find Install README.md    # open and jump to "Install"
  twain --refresh                   # reload every open document
  generate-report | twain -         # view command output
EOF
}

# Percent-encode a string for use as a twain:// query value. Iterates bytes
# (LC_ALL=C) so multibyte UTF-8 input is encoded correctly. The & 255 mask
# matters: bash 3.2 (macOS /bin/bash) sign-extends bytes >= 0x80 in the
# "'$c" ordinal conversion, which would print %FFFFFFFFFFFFFFC3 for %C3.
urlencode() (
    LC_ALL=C
    s="$1"
    out=""
    i=0
    while [ "$i" -lt "${#s}" ]; do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9._~/-]) out="$out$c" ;;
            *) out="$out$(printf '%%%02X' "$(( $(printf '%d' "'$c") & 255 ))")" ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$out"
)

abspath() (
    cd "$(dirname "$1")" && printf '%s/%s' "$(pwd)" "$(basename "$1")"
)

# The installed app bundle, resolved by path. Opening by path (never by name)
# matters: a LaunchServices name lookup for "Twain" can resolve to a stale
# build copy inside a source checkout's .build directory instead of the
# installed app.
APP=""
for candidate in "$HOME/Applications/Twain.app" "/Applications/Twain.app"; do
    if [ -d "$candidate" ]; then
        APP="$candidate"
        break
    fi
done

require_app() {
    if [ -z "$APP" ]; then
        echo "twain: Twain.app not found in ~/Applications or /Applications" >&2
        exit 1
    fi
}

# Launch Twain (without activating) before sending it a twain:// URL, so the
# URL is delivered to a running instance rather than racing app launch.
ensure_running() {
    require_app
    open -g -a "$APP"
}

BACKGROUND=0
REFRESH=0
FIND_QUERY=""
READ_STDIN=0
FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        -g|--background) BACKGROUND=1 ;;
        -f|--find)
            [ $# -ge 2 ] || { echo "twain: $1 requires an argument" >&2; exit 1; }
            FIND_QUERY="$2"
            shift
            ;;
        -r|--refresh) REFRESH=1 ;;
        --version)
            require_app
            defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString
            exit 0
            ;;
        -h|--help) usage; exit 0 ;;
        -) READ_STDIN=1 ;;
        --) shift; break ;;
        -*) echo "twain: unknown option: $1" >&2; usage >&2; exit 1 ;;
        *) FILES+=("$1") ;;
    esac
    shift
done
while [ $# -gt 0 ]; do FILES+=("$1"); shift; done

OPEN_FLAGS=()
[ "$BACKGROUND" -eq 1 ] && OPEN_FLAGS+=(-g)

if [ "$READ_STDIN" -eq 1 ]; then
    TMP=$(mktemp /tmp/twain-stdin-XXXXXX)
    mv "$TMP" "$TMP.md"
    cat > "$TMP.md"
    FILES+=("$TMP.md")
fi

if [ "$REFRESH" -eq 1 ]; then
    ensure_running
    if [ "${#FILES[@]}" -eq 0 ]; then
        open -g "twain://refresh"
    else
        for f in "${FILES[@]}"; do
            open -g "twain://refresh?file=$(urlencode "$(abspath "$f")")"
        done
    fi
    exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    if [ -n "$FIND_QUERY" ]; then
        ensure_running
        open ${OPEN_FLAGS[@]+"${OPEN_FLAGS[@]}"} "twain://search?q=$(urlencode "$FIND_QUERY")"
    else
        require_app
        open ${OPEN_FLAGS[@]+"${OPEN_FLAGS[@]}"} -a "$APP"
    fi
    exit 0
fi

require_app
for f in "${FILES[@]}"; do
    if [ ! -e "$f" ]; then
        echo "twain: no such file: $f" >&2
        exit 1
    fi
    ABS=$(abspath "$f")
    if [ -n "$FIND_QUERY" ]; then
        ensure_running
        URL="twain://open?file=$(urlencode "$ABS")&search=$(urlencode "$FIND_QUERY")"
        [ "$BACKGROUND" -eq 1 ] && URL="$URL&activate=0"
        open ${OPEN_FLAGS[@]+"${OPEN_FLAGS[@]}"} "$URL"
    else
        open ${OPEN_FLAGS[@]+"${OPEN_FLAGS[@]}"} -a "$APP" "$ABS"
    fi
done
SCRIPT

echo "Installing CLI to ~/.bin/twain..."
mkdir -p "$HOME/.bin"
install -m 755 "$TMPFILE" "$CLI_DEST"
rm -f "$TMPFILE"
echo "CLI installed to $CLI_DEST"

echo "Done. Use: twain path/to/file.md (twain --help for more)"
