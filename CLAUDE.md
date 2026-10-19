# Twain

A minimal, read-only Markdown viewer for macOS, built with SwiftUI and the [Textual](https://github.com/gonzalezreal/textual) library. Local `.html`/`.htm` files render in a `WKWebView` (see HTML gotchas).

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

## Front matter gotchas

- **The front-matter table is part of the parsed `AttributedString`, not a separate view.** `FrontMatterParser` (TwainRendering) splits the leading `---` block off, parses the body, and prepends a hand-built table carrying Foundation table presentation intents (negative identities, so they never collide with the body's) plus the `twain.frontMatter` marker attribute. Search offsets, highlight painting, the scroll estimator, print and Quick Look all work on that one string. Don't render front matter with its own SwiftUI view — it would drop out of search and skew the scroll estimate.
- **The table still needs its own `StructuredText` instance.** Textual bolds row 0 of every table and passes cell styles only `row`/`column`, so a header-less key/value table can't be told apart inside the document. `DocumentText` renders the marked slice in a second instance with `ThemedTableCellStyle(emphasis: .keyColumn)`; use `DocumentText` (not `StructuredText`) at every render site — app, print, appex.
- **Nested YAML renders as indented text inside the value cell.** GitHub nests tables; Textual cells are inline-only. Values are literal (no Markdown parsing) like GitHub; only a bare URL scalar becomes a link.

## Theme gotchas

- **Every new key added to an existing `Theme` section must be an optional Codable field** with a fallback accessor (`resolvedX` / `?? default`), even when it lands in the same commit as its section. Dev builds are installed via `install.sh` against the live `~/.config/twain/theme.json`, so that file can be written by intermediate build states. A required field makes older files fail to decode, which silently reverts the app to the default theme *and* blocks `syncUserThemeFile`'s decode gate from topping the file up. Entirely new sections may use required fields internally, but the section itself must be optional on `Theme`. Add a decode-fallback test (see `listSectionWithoutItemSpacingStillDecodes` in ThemeTests.swift).
- **Theme values wired through Textual *environment modifiers* (e.g. `.textual.listItemSpacing`) don't update on live theme reload** — Textual caches the resolved value in view `@State` and only re-resolves on a block-spacing preference change. Values wired through Textual *styles* update for free. When adding such a key, also key the `StructuredText` subtree's identity on the value (`.id(<value>)` inside the `.id("content")` used by search scrolling in ContentView.swift), and verify with a live-edit screenshot diff (launch with `TWAIN_CONFIG_DIR` pointing at a scratch config, edit the value while running, capture before/after — see Tests/screenshots/run-tests.sh for the capture pattern).

## HTML gotchas

- **HTML windows are a separate view, not a Textual mode.** `DocumentWindowContent` routes by `DocumentKind` (file extension) to `HTMLContentView`, used by both the `DocumentGroup` and folder windows. Theme, serif toggle, `DocumentPrinter`, and `SearchState` don't apply; refresh, live reload, find, print/export, zoom (`fontSize / 16` → `pageZoom`), `twain://`, and AppleScript are wired separately in that view. A new cross-cutting command must be wired in both views.
- **Never navigate the window.** `HTMLNavigationPolicy` (pure, unit-tested) allows only the document's own URL in the main frame (loads, reloads, `#fragment` jumps). Clicked links open in Twain (viewable local files) or the default app. Everything else is cancelled. Don't add a back/forward history or an address bar. That's a browser, and Twain isn't one.
- **Use `callAsyncJavaScript`, not async `evaluateJavaScript`.** The async `evaluateJavaScript` bridges its result as non-optional `Any` and fails on scripts that return `undefined`. Run helper scripts in `.defaultClient` so page globals can't interfere.
- **`WKWebView` print output is blank unless the print operation's view gets a frame** (`operation.view?.frame = webView.bounds`). Export runs the same print operation with `jobDisposition = .save`. Don't route it through `createPDF` (one endless page) or `DocumentPrinter`.
- **Read access is scoped to the file's folder** (`loadFileURL(_:allowingReadAccessTo:)`). Only the main file is watched: edits to a sibling CSS/JS file need Cmd+R.
- **`Info.plist` registers `public.html` with `LSHandlerRank` `Alternate`.** Don't raise it: Twain must never become the default browser for `.html`. Quick Look stays Markdown-only, since macOS already previews HTML.

## App icon

- **`Twain.icon` (Icon Composer) is the source; `Twain.icns` and `public/twain-icon.png` are generated** by `./make-icon.swift` (needs Xcode 26's `ictool`). Don't edit the outputs by hand. The `.icns` stays committed because CI builds with Xcode 16, which can't compile `.icon` documents.
