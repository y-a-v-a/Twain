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
  3. Installs the `twain` CLI (cli/twain) to ~/.bin/twain

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

echo "Installing CLI to ~/.bin/twain..."
mkdir -p "$HOME/.bin"
install -m 755 cli/twain "$CLI_DEST"
echo "CLI installed to $CLI_DEST"

echo "Done. Use: twain path/to/file.md (twain --help for more)"
