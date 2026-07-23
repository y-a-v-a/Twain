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
- **Waiting for Textual's async syntax highlighting must suspend, not spin.** The highlight `.task` does run under `ImageRenderer` and later passes do reflect it — but only across a real suspension (`await Task.sleep`). A nested `RunLoop.main.run` starves the chain and code prints uncolored. Regression check: `printedCodeKeepsHighlightColorsWhenPrismIsAvailable` in PrintTests.swift (needs `PACKAGE_RESOURCE_BUNDLE_PATH` — see the comment there).
- **Don't route print output through an intermediate PDF or `NSView` machinery.** Drawing a rendered PDF into a print context (PDF-in-PDF) loses text extractability, `NSHostingView.dataWithPDF` produces an empty shell, and `NSPrintOperation`'s view pagination (`knowsPageRange`/`rectForPage`) mis-places slices of ImageRenderer-backed content. Compose pages directly into a `CGContext` and hand the finished PDF to PDFKit's print operation.

## Quick Look gotchas

- **The appex is hand-assembled — SPM cannot build `.appex` targets.** `TwainQuickLook` is a plain SPM executable whose entry point is swapped to Foundation's `_NSExtensionMain` at link time (`Package.swift` linker flags); `build.sh` bundles it into `Contents/PlugIns` with `quicklook/Info.plist` and signs it with `quicklook/TwainQuickLook.entitlements` *before* re-signing the outer app. The appex must stay sandboxed and must carry its own copy of the Textual resource bundle (it is its own main bundle — without it code blocks print uncolored). The SwiftUIMath bundle (7MB of math fonts) is deliberately **not** copied into app or appex — Twain never enables Textual's `.math` extension; restore both copies if math support is ever added. `Tests/quicklook/verify-bundle.sh` (run in CI) checks all of this.
- **Never assign the preview controller's `view` in `preparePreviewOfFile`.** Quick Look attaches the controller's original view to its remote bridge before that method runs; a replaced view silently never renders and Finder shows "Extension … failed during preview". Install the hosting view as a subview (clearing previous subviews for controller reuse) — see PreviewViewController.swift.
- **The extension renders with `Theme.default`, never the user theme.** The sandbox blocks `~/.config/twain/theme.json`; don't "fix" the preview by loading it.
- **Theme/style types live in `Sources/TwainRendering`** (shared by app and appex). New members used from the app or appex need `public`; tests reach internals via `@testable import TwainRendering`.

## Theme gotchas

- **Every new key added to an existing `Theme` section must be an optional Codable field** with a fallback accessor (`resolvedX` / `?? default`), even when it lands in the same commit as its section. Dev builds are installed via `install.sh` against the live `~/.config/twain/theme.json`, so that file can be written by intermediate build states. A required field makes older files fail to decode, which silently reverts the app to the default theme *and* blocks `syncUserThemeFile`'s decode gate from topping the file up. Entirely new sections may use required fields internally, but the section itself must be optional on `Theme`. Add a decode-fallback test (see `listSectionWithoutItemSpacingStillDecodes` in ThemeTests.swift).
- **Theme values wired through Textual *environment modifiers* (e.g. `.textual.listItemSpacing`) don't update on live theme reload** — Textual caches the resolved value in view `@State` and only re-resolves on a block-spacing preference change. Values wired through Textual *styles* update for free. When adding such a key, also key the `StructuredText` subtree's identity on the value (`.id(<value>)` inside the `.id("content")` used by search scrolling in ContentView.swift), and verify with a live-edit screenshot diff (launch with `TWAIN_CONFIG_DIR` pointing at a scratch config, edit the value while running, capture before/after — see Tests/screenshots/run-tests.sh for the capture pattern).
