import Testing
import Foundation
import Textual
@testable import Twain

@MainActor
struct TaskListMarkerTests {
    /// Parses markdown and returns the plain text after task-marker expansion. Note that
    /// AttributedString carries block structure in presentation intents, not newlines, so
    /// adjacent list items concatenate directly in the plain text.
    private func expandedText(_ markdown: String) throws -> String {
        let parsed = try AttributedStringMarkdownParser(baseURL: nil)
            .attributedString(for: markdown)
        return String(parsed.expandingTaskListMarkers().characters)
    }

    @Test func checkedAndUncheckedMarkersBecomeGlyphs() throws {
        #expect(try expandedText("- [x] done\n- [ ] open") == "☑ done☐ open")
    }

    @Test func uppercaseMarkerIsRecognized() throws {
        #expect(try expandedText("- [X] done") == "☑ done")
    }

    @Test func orderedListItemsAreRecognized() throws {
        #expect(try expandedText("1. [x] done") == "☑ done")
    }

    @Test func nestedItemsAreEachExpanded() throws {
        #expect(try expandedText("- [x] parent\n  - [ ] child") == "☑ parent☐ child")
    }

    @Test func formattingAfterTheMarkerIsPreserved() throws {
        #expect(try expandedText("- [x] **bold** done") == "☑ bold done")
    }

    @Test func emptyTaskItemBecomesABareGlyph() throws {
        #expect(try expandedText("- [ ]") == "☐")
    }

    @Test func markerMidSentenceIsContent() throws {
        #expect(try expandedText("- done [x] later") == "done [x] later")
    }

    @Test func markerOutsideAListIsContent() throws {
        #expect(try expandedText("[x] not a task") == "[x] not a task")
    }

    @Test func markerInInlineCodeIsContent() throws {
        #expect(try expandedText("- `[x]` code") == "[x] code")
    }

    @Test func markerInACodeBlockIsContent() throws {
        #expect(try expandedText("```\n- [x] fenced\n```").contains("[x] fenced"))
    }

    @Test func secondParagraphOfALooseItemIsContent() throws {
        #expect(try expandedText("- first\n\n  [x] second") == "first[x] second")
    }

    @Test func sourceGateSkipsRebuildWhenNoMarkerText() throws {
        // The raw-source gate must return the parse untouched without the run-by-run rebuild…
        let parsed = try AttributedStringMarkdownParser(baseURL: nil)
            .attributedString(for: "- plain item")
        #expect(parsed.expandingTaskListMarkers(ifPresentIn: "- plain item") == parsed)
    }

    @Test func sourceGateStillExpandsWhenMarkerTextPresent() throws {
        // …and must be transparent when marker text is in the source, including the false-positive
        // case where the `[x]` is content (inline code): same output as the ungated scan.
        for markdown in ["- [x] done\n- [ ] open", "`[x]` in code"] {
            let parsed = try AttributedStringMarkdownParser(baseURL: nil)
                .attributedString(for: markdown)
            #expect(
                parsed.expandingTaskListMarkers(ifPresentIn: markdown)
                    == parsed.expandingTaskListMarkers()
            )
        }
    }

    @Test func documentWithoutMarkersIsUntouched() throws {
        let parsed = try AttributedStringMarkdownParser(baseURL: nil)
            .attributedString(for: "- plain item\n\nparagraph")
        #expect(parsed.expandingTaskListMarkers() == parsed)
    }

    @Test func cacheAppliesTheExpansionForSearchAndRendering() throws {
        // Search offsets index into the cache's plainText, so the expansion must be visible
        // there — matches found against it stay valid indices into the rendered string.
        let cache = HighlightingMarkdownCache()
        try cache.prepare(markdown: "- [x] done\n- [ ] open")
        #expect(cache.plainText == "☑ done☐ open")
        #expect(SearchState.findMatches(of: "done", in: cache.plainText) == [2..<6])
    }
}
