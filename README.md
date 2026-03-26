# Twain

A fast, minimal Markdown viewer for macOS. Read-only — no editing, just rendering.

## Requirements

- macOS 15 (Sequoia)
- Xcode 16+ / Swift 6

## Build & Run

```bash
./build.sh          # debug build
./release.sh        # release build
./run.sh file.md    # build and open a file
./clean.sh          # clean build artifacts
```

## Install

```bash
./install.sh
```

Installs `Twain.app` to `/Applications` and a CLI wrapper to `/usr/local/bin`, so you can run:

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

## Stack

- SwiftUI + [Textual](https://github.com/gonzalezreal/textual) for native Markdown rendering
- Swift Package Manager
- ~2MB release binary
