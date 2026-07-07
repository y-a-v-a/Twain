import Foundation

// GFM task-list markers (`- [x]` / `- [ ]`) are not part of CommonMark, and Apple's
// AttributedString Markdown parser (which Textual builds on) leaves them as literal list-item
// text. Textual's own post-parse hook for this kind of rewrite (SyntaxExtension) is not publicly
// constructible, so Twain applies the same post-parse substitution itself.
extension AttributedString {
    /// Replaces literal GFM task-list markers (`[x]`, `[X]`, `[ ]`) at the start of list items
    /// with checkbox glyphs (☑ / ☐), preserving each run's attributes. Returns `self` unchanged
    /// when the document contains no task items.
    func expandingTaskListMarkers() -> AttributedString {
        var output = AttributedString()
        var seenListItems: Set<Int> = []
        var didReplace = false

        // Rebuild by appending run slices rather than mutating in place: a replacement changes
        // the character count, which would invalidate the remaining runs' ranges.
        for run in runs {
            let slice = self[run.range]
            if let replacement = Self.taskMarkerExpansion(
                text: String(slice.characters),
                run: run,
                seenListItems: &seenListItems
            ) {
                didReplace = true
                output.append(AttributedString(replacement, attributes: run.attributes))
            } else {
                output.append(AttributedString(slice))
            }
        }

        return didReplace ? output : self
    }

    private static func taskMarkerExpansion(
        text: String,
        run: Runs.Run,
        seenListItems: inout Set<Int>
    ) -> String? {
        // GFM only recognizes a marker directly after the list bullet: the run must sit in a
        // paragraph that is the innermost block of a list item.
        guard let components = run.presentationIntent?.components,
              case .paragraph = components.first?.kind,
              let listItem = components.first(where: {
                  if case .listItem = $0.kind { return true }
                  return false
              })
        else { return nil }

        // Only the first run of each list item is eligible; later runs (bold spans, a loose
        // item's second paragraph) are content even if they happen to start with `[x]`.
        guard seenListItems.insert(listItem.identity).inserted else { return nil }

        // A literal `[x]` in inline code is content, not a marker.
        if run.inlinePresentationIntent?.contains(.code) == true { return nil }

        for (marker, glyph) in [("[x]", "☑"), ("[X]", "☑"), ("[ ]", "☐")] {
            if text == marker {
                return glyph
            }
            if text.hasPrefix(marker + " ") {
                return glyph + text.dropFirst(marker.count)
            }
        }

        return nil
    }
}
