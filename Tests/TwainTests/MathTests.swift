import Testing
import Foundation
@testable import Twain
@testable import TwainRendering

@MainActor
struct MathTests {
    private func parse(_ markdown: String) throws -> AttributedString {
        let cache = HighlightingMarkdownCache()
        try cache.prepare(markdown: markdown)
        return cache.attributedString
    }

    private func attachmentCount(_ string: AttributedString) -> Int {
        string.characters.filter { $0 == "\u{FFFC}" }.count
    }

    @Test func inlineAndBlockMathBecomeAttachments() throws {
        let parsed = try parse("Area is $A = \\pi r^2$.\n\n$$E = mc^2$$\n")
        #expect(attachmentCount(parsed) == 2)
        #expect(!String(parsed.characters).contains("\\pi"))
    }

    @Test func mathInCodeIsLeftAlone() throws {
        let parsed = try parse("Use `$x$` literally.\n\n```\n$$y$$\n```\n")
        #expect(attachmentCount(parsed) == 0)
    }

    @Test func printParserRendersMathToo() throws {
        let parsed = try PrintMarkdownParser(baseURL: nil).attributedString(for: "$x^2$")
        #expect(attachmentCount(parsed) == 1)
    }

    @Test func searchStaysAlignedAroundFormulas() throws {
        let markdown = "Before $x^2$ after, and $$y$$ after again."
        let cache = HighlightingMarkdownCache()
        let state = SearchState(layout: Theme.default.blockLayout(fontSize: 16))
        state.updateDocument(markdown: markdown, using: cache)
        state.updateQuery("after")

        let text = cache.plainText
        let characters = Array(text)
        #expect(state.matches.count == 2)
        for match in state.matches {
            #expect(String(characters[match]).lowercased() == "after")
        }
    }

    /// Textual's inline-math pattern still matches "$5 and $" as a formula. Fixed by tightening
    /// the pattern to pandoc's `tex_math_dollars` rules in the y-a-v-a/textual fork; once Twain's
    /// pin includes that, `withKnownIssue` reports the fix and this wrapper should be removed.
    @Test func proseDollarAmountsStayText() throws {
        let parsed = try parse("It costs $5 and $10 today.")
        withKnownIssue("Textual inline-math pattern treats prose dollar amounts as math") {
            #expect(attachmentCount(parsed) == 0)
            #expect(String(parsed.characters) == "It costs $5 and $10 today.")
        }
    }
}
