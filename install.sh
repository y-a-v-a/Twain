#!/bin/bash
set -euo pipefail

./release.sh

APP_SOURCE=".build/release/Twain.app"
APP_DEST="$HOME/Applications/Twain.app"
CLI_DEST="/usr/local/bin/twain"

mkdir -p "$HOME/Applications"
echo "Installing Twain.app to ~/Applications..."
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

echo "Installing CLI to /usr/local/bin/twain..."
cat > "$CLI_DEST" << 'SCRIPT'
#!/bin/bash
if [ $# -eq 0 ]; then
    open -a Twain
else
    for f in "$@"; do
        open -a Twain "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    done
fi
SCRIPT
chmod +x "$CLI_DEST"

echo "Done. Use: twain path/to/file.md"
