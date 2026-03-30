#!/bin/bash
set -euo pipefail

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
if [ $# -eq 0 ]; then
    open -a Twain
else
    for f in "$@"; do
        open -a Twain "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    done
fi
SCRIPT

echo "Installing CLI to ~/.bin/twain..."
mkdir -p "$HOME/.bin"
install -m 755 "$TMPFILE" "$CLI_DEST"
rm -f "$TMPFILE"
echo "CLI installed to $CLI_DEST"

echo "Done. Use: twain path/to/file.md"
