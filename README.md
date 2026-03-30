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
twain a.md b.md   # opens each in its own window
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+O | Open file |
| Cmd++ | Increase font size |
| Cmd+- | Decrease font size |
| Cmd+0 | Reset font size |
| Cmd+Shift+F | Toggle serif font |

Font size and font style preferences are saved and restored across app restarts.

## Features

- Native syntax highlighting in code blocks (automatic language detection)
- Sans-serif and serif font options
- Persistent font size and style preferences
- Light and dark mode support
- Multiple window support

## Stack

- SwiftUI + [Textual](https://github.com/gonzalezreal/textual) for native Markdown rendering with Prism.js syntax highlighting
- Swift Package Manager
- ~2MB release binary
