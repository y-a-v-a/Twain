#!/bin/bash
set -euo pipefail

./release.sh

APP_SOURCE=".build/release/mdv.app"
APP_DEST="/Applications/mdv.app"
CLI_DEST="/usr/local/bin/mdv"

echo "Installing mdv.app to /Applications..."
rm -rf "$APP_DEST"
cp -R "$APP_SOURCE" "$APP_DEST"

echo "Installing CLI to /usr/local/bin/mdv..."
cat > "$CLI_DEST" << 'SCRIPT'
#!/bin/bash
if [ $# -eq 0 ]; then
    open -a mdv
else
    for f in "$@"; do
        open -a mdv "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
    done
fi
SCRIPT
chmod +x "$CLI_DEST"

echo "Done. Use: mdv path/to/file.md"
