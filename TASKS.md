# mdv — Minimal Markdown Viewer for macOS

## Context
A fast, read-only macOS desktop app for viewing `.md` files. No editing — just open and read rendered Markdown as quickly as possible. Multi-window, minimal UI.

## Stack
- Swift / SwiftUI, macOS 14+ (Sonoma)
- MarkdownUI (third-party, for native Markdown rendering)
- Swift Package Manager

## Tasks

- [x] **Project setup**: Create SPM-based macOS app package with `Package.swift`, add MarkdownUI dependency
- [x] **App entry point**: `@main` App struct using `DocumentGroup` for multi-window `.md` file support (gives us Cmd+O, recent files, multiple windows for free)
- [x] **Document model**: `MarkdownDocument` conforming to `FileDocument` — reads `.md`/`.markdown` files as plain text
- [x] **Content view**: Scrollable view rendering Markdown via MarkdownUI `Markdown()` view, clean readable typography
- [x] **File type registration**: UTType declaration for `.md` / `.markdown` so the app can be set as default handler
- [x] **Light/dark mode**: Ensure proper rendering in both appearances (largely free via SwiftUI, verify MarkdownUI theme)
- [ ] **Build scripts**: `build.sh` (debug build), `release.sh` (release build), `run.sh` (build & open app), `clean.sh` (clean build artifacts)
- [ ] **Build & test**: Verify the app launches fast, opens files, renders correctly, handles multiple windows
