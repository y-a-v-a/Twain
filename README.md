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

## Packaged builds

Downloadable builds are produced by the [`Package` workflow](.github/workflows/package.yml),
triggered by hand: **Actions → Package → Run workflow**, enter a version string (e.g. `1.5`).
The run stamps the version into `Info.plist`, builds a release bundle, and uploads
`Twain-<version>.zip` as a workflow artifact (GitHub keeps artifacts for 90 days).

These are Apple Silicon (arm64) builds with only an ad-hoc signature — no Apple
Developer ID, not notarized — so Gatekeeper refuses a downloaded copy by default.
After unzipping, either clear the quarantine flag:

```bash
xattr -d com.apple.quarantine Twain.app
```

or attempt to open it once and allow it via **System Settings → Privacy & Security → Open Anyway**.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd+, | Open Settings (edit theme) |
| Cmd++ | Increase font size |
| Cmd+- | Decrease font size |
| Cmd+0 | Reset font size |
| Cmd+R | Refresh file from disk (documents also auto-reload on change) |
| Cmd+Shift+F | Toggle serif font |
| Cmd+P | Print (the panel's PDF menu covers Save as PDF and friends) |
| Cmd+Shift+E | Export as PDF |

Font size and font style preferences are saved and restored across app restarts.

## Theming

Twain renders with a built-in theme that you can fully customize via a JSON file at
`~/.config/twain/theme.json`. The file is **created automatically** on first launch, seeded
with the default theme — there's nothing to copy or set up by hand.

The easiest way in: open **Settings** (`Cmd+,`, under the **Twain** menu) and click
**Edit Theme…**. That opens `~/.config/twain/theme.json` in your default editor (creating it
first if it's missing). Edits are **applied live** — save the file and open windows re-style
instantly, no restart needed.

You can tune colors (hex `#RRGGBB`), heading scales, code-block styling, paragraph line height
(`paragraph.lineSpacingScale`), window padding (`layout.contentInset`), and more. See the
repo's `theme.json` for all available options. Theme files stay forward-compatible: any section
you omit falls back to its built-in default, and if the file is missing or invalid Twain uses
the default theme.

## Quick Look

Twain ships a Quick Look extension: select a `.md` file in Finder, press space, and the
preview renders with Twain's default theme — headings, tables, syntax-highlighted code
and all. It registers automatically the first time you launch the installed app. If
previews still show plain text, enable it under **System Settings → General →
Login Items & Extensions → Quick Look**, or check registration with:

```bash
pluginkit -m -p com.apple.quicklook.preview | grep twain
```

The very first preview after a login can take a moment while macOS spins up the
extension process; subsequent previews are instant.

Two limitations, both imposed by the extension sandbox: previews always use the built-in
default theme (the extension can't read `~/.config/twain/theme.json`), and images
referenced by the document aren't shown (the extension may only read the previewed file).

## Features

- 🔄 Live reload: open documents follow the file on disk (atomic saves included)
- 🌈 Native syntax highlighting in code blocks (automatic language detection)
- 🔤 Sans-serif and serif font options
- 💾 Persistent font size and style preferences
- 🎨 Customizable theming via external JSON — auto-created, editable from Settings, applied live
- 🌗 Light and dark mode support
- 🖨️ Print and PDF export with the on-screen theme: real selectable text, page breaks that
  never slice a line, code blocks wrapped for paper
- 🪟 Multiple window support
- 👀 Quick Look: select a Markdown file in Finder, press space, get Twain's rendering
- 🔗 Scriptable via the `twain://` URL scheme and CLI — agent-friendly by design
- 🤖 Agent skill: a harness-agnostic [skill](https://agentskills.io) (`skills/twain-markdown-viewer/`)
  that teaches coding agents to open Markdown files in Twain
- 📜 AppleScript support: introspect and drive open documents from scripts via `osascript`

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

### Agent skill

`skills/twain-markdown-viewer/` is a harness-agnostic [agent skill](https://agentskills.io)
that teaches a coding agent to open Markdown files in Twain when the user asks to *open,
show, view, or preview* one (but not when asked to *read* or *study* it — that's the
agent's job). Install it by symlinking the directory into your agent's skills location,
e.g. for Claude Code:

```bash
ln -s "$(pwd)/skills/twain-markdown-viewer" ~/.claude/skills/
```

### AppleScript

Where the URL scheme is write-only, AppleScript adds the introspection half — ask Twain what
is open and what it shows, via `osascript`:

```applescript
tell application "Twain"
    count documents
    get name of every document
    get path of document 1
    get source text of document 1     -- raw Markdown, follows live reloads
    get rendered text of document 1   -- plain text after Markdown parsing
    refresh document 1                -- re-read from disk
    search document 1 for "Install"   -- open search, jump to first match
    close document 1                  -- closes the window; disk is untouched
end tell
```

One-liners for scripts and agents:

```bash
osascript -e 'tell application "Twain" to get path of every document'
osascript -e 'tell application "Twain" to search document "README.md" for "Theming"'
osascript -e 'tell application "Twain" to close every document'
```

Documents are addressable by index (registration order) or by file name. The first script
that targets Twain triggers a one-time macOS Automation permission prompt for the calling
app. The dictionary is defined in `Twain.sdef`; end-to-end checks live in
`Tests/applescript/run-tests.sh` (macOS only).

## Development & Testing

```bash
swift test               # unit tests: search, URL command parsing, file watching,
                         # notification payloads (macOS only)
Tests/cli/run-tests.sh   # CLI behavior tests against a stubbed `open`
                         # (runs on macOS and Linux, no Twain.app needed)
Tests/applescript/run-tests.sh   # end-to-end AppleScript checks: builds the app,
                                 # opens a fixture, drives it with osascript (macOS only,
                                 # not in CI — Apple Events need a consent prompt)
```

Both suites run in CI on every push (`.github/workflows/ci.yml`): the Swift job builds,
tests, and assembles the app bundle on a macOS runner; the CLI job runs on Linux. Note the
`FileWatcher` tests are timing-based (the watcher arms asynchronously and debounces), so
they take a few seconds.

## Stack

- SwiftUI + [Textual](https://github.com/gonzalezreal/textual) for native Markdown rendering with Prism.js syntax highlighting
- Swift Package Manager
- ~24MB installed, Quick Look extension and math fonts included — still an order of
  magnitude smaller than an Electron-based Markdown viewer

## License

[MIT](LICENSE)

---

© 2026 Vincent Bruijn
