# Search feature — review fixes

Task list from the stern review of the in-document search changeset
(`d6b98c5`..`1ae07c0`). Ordered by priority. Files: `SearchBar.swift`,
`BlockLayoutMetrics.swift`, `ContentView.swift`, `ThemedStyle.swift`.

---

## Blockers / majors

### 1. Enforce offset alignment between the two parses
- [x] **Problem:** matches are computed against `HighlightingMarkdownCache.plainText`
  (one parser instance) but applied as character offsets to a *separately
  re-parsed* `AttributedString` inside `HighlightingMarkdownParser` (another
  instance). Correctness silently depends on both producing identical character
  sequences. The current guard (`SearchBar.swift:40-45`) only catches count
  *overflow*, not equal-count-but-shifted content.
- [x] **Fix (minimal):** in `HighlightingMarkdownParser.attributedString`, before
  mapping any offset, assert `result.characters.count == <expected count>`. On
  mismatch, return the unhighlighted `result` rather than mapping blindly.
- [x] **Fix (preferred):** highlight the same `AttributedString` the cache already
  parsed instead of re-parsing — see task 6.
- Location: `SearchBar.swift:8,30,32,40-53`

### 2. Stop re-parsing the whole document on every keystroke / next-prev
- [x] **Problem:** `updateQuery` / `nextMatch` / `previousMatch` bump
  `renderRevision` → `displayText` changes → `StructuredText` re-runs
  `HighlightingMarkdownParser.attributedString`, which does a fresh full-document
  `baseParser.attributedString(for:)`. The render-side parser has no cache
  (only `SearchState` does). Large documents lag per character.
- [x] **Fix:** reuse the cached base `AttributedString` on the render side and only
  re-apply background colors for the current `matches` / `currentMatchIndex`,
  so a query/index change is O(matches) restyle, not O(document) reparse.
- Location: `ContentView.swift:38-49`, `SearchBar.swift:32`

---

## Minors / suspicious choices

### 3. U+E000 separator can truncate real document content while searching
- [x] **Problem:** `displayText` appends `\u{E000}` + `renderRevision` to force a
  re-parse; the parser strips everything from the first `\u{E000}`. A document
  that legitimately contains U+E000 loses everything after it *while searching*.
- [x] **Fix:** drive the re-parse off an explicit revision input instead of
  smuggling it through the markup string; or strip the sentinel defensively and
  document the assumption.
- Location: `SearchBar.swift:26,58-64`, `ContentView.swift:38-42`

### 4. Document the transient invariant violation (label count vs. highlights)
- [x] **Problem:** during the refresh-while-searching window, the guard skips
  out-of-range matches, so the label can read "5 of 10" while fewer than 10 are
  highlighted. Self-correcting, but it's the exact invariant CLAUDE.md calls out.
- [x] **Fix:** add a comment acknowledging the transient, or recompute the label
  from the matches actually rendered.
- Location: `SearchBar.swift:41-45,641-647`

### 5. Make `query` non-publicly-settable
- [x] **Problem:** `var query` is freely settable; everything else uses
  `private(set)` + a mutator to keep `matches` in sync. A stray external write
  desyncs matches from the displayed query.
- [x] **Fix:** make it `private(set) var query` and route all writes through
  `updateQuery`.
- Location: `SearchBar.swift:131,200-205`

### 6. Collapse to a single parse (single source of truth)
- [x] **Problem:** two parser instances, two parses of the same input. Source of
  tasks 1 and 2.
- [x] **Fix:** parse once into the cache; have the render-side `MarkupParser`
  take that `AttributedString` and only overlay background colors. Removes the
  drift risk and the double-parse cost together.
- Location: `SearchBar.swift:7-65`, `ContentView.swift:44-49`

### 7. Remove/clarify hardcoded `theme.blockLayout(fontSize: 16)` in styles
- [x] **Problem:** harmless today (style code only reads size-independent fields),
  but reads like a bug and invites one.
- [x] **Fix:** pass the live font size, or add a parameterless accessor for the
  size-independent metrics.
- Location: `ThemedStyle.swift:10,44,84,94,140,152`

### 8. Note the width-independent wrap estimate
- [x] **Problem:** `estimatedLineUnits` assumes 72 chars/line regardless of window
  width, so scroll accuracy drifts as the window resizes.
- [x] **Fix:** comment that this is a deliberate approximation (or feed actual
  content width if scroll accuracy becomes a complaint).
- Location: `BlockLayoutMetrics.swift`, `SearchBar.swift:451-460`

### 9. Replace `NSApp.currentEvent` shift-detection in `onSubmit`
- [x] **Problem:** reads global event state to choose direction — fragile coupling.
- [x] **Fix:** rely on the existing Cmd-G / Cmd-Shift-G commands, or a dedicated
  binding, instead of inspecting the current event.
- Location: `SearchBar.swift:591-597`

---

## Tests to add (currently zero coverage)

Pure, `@MainActor` logic — eminently testable.

- [x] `findMatches`: empty query; no match; overlapping candidates
  (`"aa"` in `"aaaa"` → 2 non-overlapping); case-insensitivity; multi-grapheme
  query (emoji/combining marks) → grapheme-based offsets.
- [x] Offset-alignment invariant: across a markdown corpus,
  `cache.plainText.count` == render-side parsed `characters.count` (guards task 1).
- [x] `rebuildMatches(resetSelection: false)`: current match preserved by
  `lowerBound` after an edit that shifts/removes earlier matches; index clamps
  when match count shrinks.
- [x] `nextMatch` / `previousMatch`: wraparound at both ends; no-op when empty.
- [x] Refresh-while-searching: `updateDocument` with an active query leaves
  `currentMatchIndex` valid and never traps.
- [ ] `currentMatchFraction`: returns 0…1 (never NaN) for empty doc, single block,
  and matches inside code block / table / heading; div-by-zero guards
  (`weight == 0`, empty `rowRanges`). _(not yet written — beyond the order's step 3)_
- [ ] `topLevelBlockRuns`: a table collapses to one block (not one-per-cell);
  `tableRowRanges` count equals source row count. _(not yet written — beyond the order's step 3)_

---

## Suggested order

1. Task 6 (single parse) — subsumes tasks 1 and 2.
2. If 6 is deferred: task 1 (assert) then task 2 (render-side cache).
3. Add the `findMatches` + `rebuildMatches` + offset-alignment tests.
4. Tasks 3, 5 (cheap correctness/safety).
5. Tasks 4, 7, 8, 9 (clarity/robustness).
