# Review: whole codebase (optimization & size) — 2026-07-23

**Intent:** find bundle-size and code-level optimization/reduction opportunities after the Quick Look appex grew the install from ~13MB to ~24MB.
**Result:** 0 blockers, 4 major, 7 minor, 1 nit. Reviewer: Codex (gpt-5.6-sol via codex-cli 0.145.0). No reconciliation round needed — no contested Blocker/Major.

## Findings

- [Accept · Major · size] build.sh:47,62 — SwiftUIMath resource bundle (7.1MB) is copied into both app and appex, but Twain never enables Textual's `.math` syntax extension (verified: `syntaxExtensions` defaults to `[]`; no Twain code passes any) → copy only `textual_Textual.bundle`; **~14.2MB saved** (24MB → ~10MB). Restore if math support is ever enabled.
- [Accept · Major · size] build.sh:40,58 — release executables ship unstripped (~62k/56k local symbols, ~3.5MB of string tables) → `strip -x` both binaries after copy, before signing; **~2.5–3MB saved**. Must re-verify appex with `Tests/quicklook/verify-bundle.sh` + `qlmanage` (principal class is Info.plist-discovered, so `strip -x` is expected safe).
- [Accept · Major · performance] SearchBar.swift:64,298 — match highlighting maps every match with `index(startIndex, offsetBy:)` from the string start (verified), making frequent-match searches quadratic → advance a single cursor monotonically over the sorted matches.
- [Accept · Major→Minor · performance] TaskListMarkers.swift:11 — every parse rebuilds a full `AttributedString` run-by-run even when no task marker exists (verified; `didReplace` only discards it afterward) → cheap raw-source guard (`[x]`/`[X]`/`[ ]` substring check) before rebuilding. Downgraded: cost is allocation churn per parse, not algorithmic.
- [Accept · Minor · performance] SearchBar.swift:188 — `updateLayout` re-runs the full document search on every resize/zoom/theme change (verified `rebuildMatches` depends only on `renderedText`, which layout can't change) → drop the call from `updateLayout`, keep in `updateDocument`/`updateQuery`.
- [Accept · Minor · performance/maintainability] ContentView.swift:6 — `document` stored property is unused after `init` (verified) and pins the pre-reload text buffer for the window's lifetime → delete the stored property.
- [Accept · Minor · maintainability] PreviewViewController.swift:27 — each `preparePreviewOfFile` adds another hosting subview; a reused controller would accumulate render trees → assign `view = NSHostingView(...)` directly, dropping the constraint plumbing.
- [Defer · Minor · performance] ContentView.swift:133 / SearchBar.swift:331 — duplicated initial layout passes and per-block `String` allocation in estimators. Real but micro; the `initial: true` removal has init-order risk that needs its own careful pass.
- [Defer · Minor · performance] DocumentPrinter.swift:249,384 — print/export parses the document twice → share a parse cache. Real, but an infrequent user-initiated path.
- [Defer · Minor · size] Package.swift:23,34 — trial `-Xlinker -dead_strip` (~0.3–1MB, must measure; appex extension-loading must be re-tested).
- [Defer · Minor · size] Package.swift:16 — true code sharing needs Textual/TwainRendering as a *dynamic* product in `Contents/Frameworks` with runpaths + nested signing; ~1–2MB for high complexity. Second-stage packaging project at most.
- [Reject · Nit · performance] ThemedStyle.swift:123 — transient `[CGRect]` per table-background draw — *rejected: negligible; Canvas draws are infrequent and the helper reads clearly.*

## Recommended order

1. Stop copying SwiftUIMath bundles (−14.2MB) and add `strip -x` (−~3MB): **~24MB → ~7MB**, no behavior change expected; re-run bundle + Quick Look checks.
2. The four accepted code fixes (search cursor, task-marker guard, `updateLayout`, dead `document` property, appex `loadView`).
3. Deferred items only if motivated later; the dynamic-library conversion is not worth it at this size.

## Reconciled

None contested at review time — no Discuss items; the only Reject was a Nit.

## Outcomes (applied 2026-07-23)

All 7 accepted findings applied; suite grew 98 → 103 tests, all passing. Installed bundle:
**24MB → 5.4MB** (math-bundle removal + `strip -x` beat the ~7MB estimate).

One empirical correction: finding 11's *proposed fix* (assign `view = NSHostingView(...)` in
`preparePreviewOfFile`) breaks Quick Look — the controller's original view is attached to the
remote bridge before that method runs, so the replaced view never renders and Finder reports
"Extension failed during preview". The underlying concern (accumulating hosting views on
controller reuse) was real and is fixed by clearing subviews before adding the new hosting
view. Recorded as a gotcha in CLAUDE.md.
