# Twain

A fast, minimal Markdown viewer for macOS. Read-only — no editing, just rendering.

![Twain Test Document](Twain.png)

## Requirements

- macOS 15 (Sequoia)
- Xcode 16+ / Swift 6

## Build & Run

```bash
./build.sh                 # debug build
./build.sh --release       # release build
./build.sh --run           # debug build and open
./build.sh --clean         # clean build artifacts
```

## Install

```bash
./install.sh
```

Installs `Twain.app` to `~/Applications` and a CLI wrapper to `~/.bin`, so you can run:

```bash
twain file.md
twain a.md b.md                 # opens each in its own window
twain -g report.md              # open without stealing focus
twain --find "Install" file.md  # open and jump to the first match
twain --refresh                 # reload every open document from disk
generate-report | twain -       # render stdin
```

See `twain --help` for all options.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd++ | Increase font size |
| Cmd+- | Decrease font size |
| Cmd+0 | Reset font size |
| Cmd+R | Refresh file from disk (documents also auto-reload on change) |
| Cmd+Shift+F | Toggle serif font |

Font size and font style preferences are saved and restored across app restarts.

## Theming

Twain supports custom themes via a JSON file at `~/.config/twain/theme.json`. Copy the included `theme.json` as a starting point:

```bash
mkdir -p ~/.config/twain
cp theme.json ~/.config/twain/theme.json
```

Edit colors (hex `#RRGGBB`), heading scales, code block styling, and more. See `theme.json` for all available options. If the file is missing or invalid, Twain falls back to its built-in defaults.

## Features

- Live reload: open documents follow the file on disk (atomic saves included)
- Native syntax highlighting in code blocks (automatic language detection)
- Sans-serif and serif font options
- Persistent font size and style preferences
- Customizable theming via external JSON
- Light and dark mode support
- Multiple window support
- Scriptable via the `twain://` URL scheme and CLI — agent-friendly by design

## Agents & Automation

Twain is built to pair with coding agents and scripts: write a Markdown file and the open
window re-renders automatically — no integration needed. For everything else there is the
`twain://` URL scheme, usable from any process via `open`:

| URL | Action |
|-----|--------|
| `twain://refresh` | Reload every open document from disk |
| `twain://refresh?file=/abs/path.md` | Reload one document |
| `twain://search?q=text` | Search all open documents, jump to the first match |
| `twain://search?q=text&file=/abs/path.md` | Search one open document |
| `twain://open?file=/abs/path.md` | Open a file |
| `twain://open?file=/abs/path.md&search=text` | Open and jump to the first match of `text` |
| `twain://open?file=/abs/path.md&activate=0` | Open without bringing Twain to the front |

File paths must be absolute and query values percent-encoded:

```bash
open -g "twain://open?file=/tmp/plan.md&search=Phase%202"
```

The installed `twain` CLI wraps all of this (`--refresh`, `--find`, `--background`, stdin via
`twain -`) so agents don't need to build URLs by hand.

## Stack

- SwiftUI + [Textual](https://github.com/gonzalezreal/textual) for native Markdown rendering with Prism.js syntax highlighting
- Swift Package Manager
- ~2MB release binary
