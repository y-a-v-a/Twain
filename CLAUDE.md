# Twain

A minimal, read-only Markdown viewer for macOS, built with SwiftUI and the [Textual](https://github.com/gonzalezreal/textual) library.

## Code style

- Keep the codebase small and flat — no unnecessary abstractions.
- Follow the existing patterns: `@State` for view state, `FocusedValue` for menu commands, `Theme` for all visual styling.

## Before writing code

When implementing a non-trivial feature, briefly describe:
1. **Data flow** — where does each piece of state live, what mutates it, what observes it?
2. **Invariants** — what properties must always hold? (e.g. "match count shown in UI equals highlights rendered")
3. **Failure modes** — what inputs or interactions would break the naive approach?

Do this before producing implementation code. A few sentences is fine — the goal is to catch design issues early, not to write a document.

## Print/PDF gotchas

- **`ImageRenderer` needs a warm-up pass, and each pass's draw closure is single-shot.** The first render pass reports a pre-settlement layout (text measured unwrapped — a fraction of the real height), so `DocumentPrinter.makePDFData` discards it and measures on the second pass. Calling a pass's `draw(context)` more than once drops text runs and drifts positions; every drawing operation (break scan, each page) gets its own render pass. Symptoms of regressing this: exported pages start mid-document, or only monospaced text survives.
- **Don't route print output through an intermediate PDF or `NSView` machinery.** Drawing a rendered PDF into a print context (PDF-in-PDF) loses text extractability, `NSHostingView.dataWithPDF` produces an empty shell, and `NSPrintOperation`'s view pagination (`knowsPageRange`/`rectForPage`) mis-places slices of ImageRenderer-backed content. Compose pages directly into a `CGContext` and hand the finished PDF to PDFKit's print operation.

## Theme gotchas

- **Every new key added to an existing `Theme` section must be an optional Codable field** with a fallback accessor (`resolvedX` / `?? default`), even when it lands in the same commit as its section. Dev builds are installed via `install.sh` against the live `~/.config/twain/theme.json`, so that file can be written by intermediate build states. A required field makes older files fail to decode, which silently reverts the app to the default theme *and* blocks `syncUserThemeFile`'s decode gate from topping the file up. Entirely new sections may use required fields internally, but the section itself must be optional on `Theme`. Add a decode-fallback test (see `listSectionWithoutItemSpacingStillDecodes` in ThemeTests.swift).
- **Theme values wired through Textual *environment modifiers* (e.g. `.textual.listItemSpacing`) don't update on live theme reload** — Textual caches the resolved value in view `@State` and only re-resolves on a block-spacing preference change. Values wired through Textual *styles* update for free. When adding such a key, also key the `StructuredText` subtree's identity on the value (`.id(<value>)` inside the `.id("content")` used by search scrolling in ContentView.swift), and verify with a live-edit screenshot diff (launch with `TWAIN_CONFIG_DIR` pointing at a scratch config, edit the value while running, capture before/after — see Tests/screenshots/run-tests.sh for the capture pattern).
