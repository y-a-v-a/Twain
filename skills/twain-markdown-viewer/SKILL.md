---
name: twain-markdown-viewer
description: >-
  Open Markdown files or local HTML pages in Twain, the macOS Markdown viewer,
  so the user can look at them rendered. Use when the user asks to open, show,
  view, display, or preview a Markdown file (or Markdown output), or an HTML
  page the agent built, for themselves — e.g. "open README.md", "show me the
  plan", "preview the report.html you made". Do NOT use when the user asks the
  agent to read, study, check, or analyze a file; that is a request for the
  agent to consume the content itself. Requires macOS with Twain installed
  (the `twain` CLI).
license: MIT
metadata:
  author: Vincent Bruijn
  homepage: https://github.com/y-a-v-a/twain
---

# Twain Markdown viewer

Twain is a read-only Markdown viewer for macOS with a `twain` CLI. It also
displays local HTML pages (`.html`/`.htm`) without browsing: the window shows
only that file, and clicked web links open in the user's browser. This skill
opens files in it for the **user** to look at. It never replaces the agent
reading a file itself.

## When to use

- The user asks to *open, show, view, display, or preview* a Markdown file:
  "open README.md", "show me docs/plan.md", "let me see the changelog".
- The user wants to look at Markdown content you just produced (a report,
  a summary, a plan).
- The user wants to see an HTML page you built (a report, dashboard, chart,
  prototype).

## When NOT to use

- "read README.md", "study the docs", "check CHANGELOG.md for X" — the user
  wants *you* to consume the content. Read the file directly instead.
- Files that are neither Markdown nor HTML. Twain renders only those two.
- Websites. Twain doesn't fetch or browse remote URLs.

## How

Open a file (relative or absolute paths both work):

```bash
twain README.md
```

Multiple files open in separate windows:

```bash
twain README.md CHANGELOG.md
```

Useful options:

| Command | Effect |
|---------|--------|
| `twain -g file.md` | Open without stealing focus — prefer this when opening proactively while the user is mid-task |
| `twain --find "text" file.md` | Open and jump to the first match of `text` |
| `twain --refresh` | Re-read every open document from disk |
| `some-command \| twain -` | Render stdin (e.g. Markdown you generated without a file; input starting with `<!doctype html>` or `<html>` opens as an HTML page) |

Notes:

- Open documents live-reload when the file changes on disk, so after editing a
  file already shown in Twain, no action is needed — `--refresh` is only for
  forcing a re-read. HTML pages keep their scroll position across reloads.
- HTML pages can load sibling files (CSS, JS, images) from their own folder
  but not from parent folders. Keep a page self-contained or put its assets
  next to it. CDN `<script>`/`<link>` tags work.
- The CLI exits non-zero with `twain: no such file: <path>` if the file does
  not exist, and errors if Twain.app is not installed in `~/Applications` or
  `/Applications`. Report that to the user rather than retrying.
- Showing Markdown you just generated: prefer writing it to a file and opening
  that (the user keeps a live-reloading window); use `twain -` only for
  throwaway output.
