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
