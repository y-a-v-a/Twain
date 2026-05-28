import Testing
import Foundation
@testable import Twain

@MainActor
struct SearchStateTests {
    private func makeState() -> SearchState {
        SearchState(layout: Theme.default.blockLayout(fontSize: 16))
    }

    private func makeState(contentWidth: CGFloat) -> SearchState {
        SearchState(layout: Theme.default.blockLayout(fontSize: 16, contentWidth: contentWidth))
    }

    // MARK: - findMatches (pure)

    @Test func findsAllNonOverlappingMatches() {
        #expect(SearchState.findMatches(of: "aa", in: "aaaa") == [0..<2, 2..<4])
    }

    @Test func findMatchesIsCaseInsensitive() {
        #expect(SearchState.findMatches(of: "ab", in: "xxABxxab") == [2..<4, 6..<8])
    }

    @Test func findMatchesReturnsEmptyWhenAbsent() {
        #expect(SearchState.findMatches(of: "zzz", in: "abcabc").isEmpty)
    }

    @Test func findMatchesCountsGraphemesNotScalars() {
        // Offsets must be in Character units so they line up with AttributedString.characters.
        #expect(SearchState.findMatches(of: "👍", in: "a👍b👍c") == [1..<2, 3..<4])
    }

    // MARK: - Query / navigation through the public API

    @Test func updateQuerySelectsFirstMatch() {
        let state = makeState()
        state.updateDocument(markdown: "foo foo foo", using: HighlightingMarkdownCache())
        state.updateQuery("foo")
        #expect(state.matchCount == 3)
        #expect(state.currentMatchIndex == 0)
    }

    @Test func navigationWrapsAtBothEnds() {
        let state = makeState()
        state.updateDocument(markdown: "a a a", using: HighlightingMarkdownCache())
        state.updateQuery("a")
        #expect(state.matchCount == 3)

        state.previousMatch()            // 0 -> last
        #expect(state.currentMatchIndex == 2)
        state.nextMatch()                // last -> 0
        #expect(state.currentMatchIndex == 0)
    }

    @Test func navigationIsNoOpWithoutMatches() {
        let state = makeState()
        state.updateDocument(markdown: "hello world", using: HighlightingMarkdownCache())
        state.updateQuery("zzz")
        #expect(!state.hasMatches)
        state.nextMatch()
        state.previousMatch()
        #expect(state.currentMatchIndex == 0)
    }

    // MARK: - Selection preservation across document edits

    @Test func selectionClampsWhenMatchesShrink() {
        let state = makeState()
        let cache = HighlightingMarkdownCache()
        state.updateDocument(markdown: "foo foo foo", using: cache)
        state.updateQuery("foo")
        state.nextMatch()
        state.nextMatch()                // last match selected
        #expect(state.currentMatchIndex == 2)

        state.updateDocument(markdown: "foo", using: cache)   // only one match remains
        #expect(state.matchCount == 1)
        #expect(state.currentMatchIndex == 0)                 // clamped, never out of range
    }

    @Test func selectionFollowsMatchAfterEdit() {
        let state = makeState()
        let cache = HighlightingMarkdownCache()
        state.updateDocument(markdown: "foo foo foo", using: cache)
        state.updateQuery("foo")
        state.nextMatch()
        state.nextMatch()
        let previousLowerBound = state.matches[state.currentMatchIndex].lowerBound

        state.updateDocument(markdown: "zzz foo foo foo", using: cache)
        #expect(state.matchCount == 3)
        // Contract: land on the first match at or after the previously selected position.
        let expected = state.matches.firstIndex { $0.lowerBound >= previousLowerBound }
            ?? (state.matchCount - 1)
        #expect(state.currentMatchIndex == expected)
    }

    @Test func resetClearsQueryAndMatches() {
        let state = makeState()
        state.updateDocument(markdown: "foo foo", using: HighlightingMarkdownCache())
        state.updateQuery("foo")
        #expect(state.hasMatches)

        state.reset()
        #expect(state.query.isEmpty)
        #expect(!state.hasMatches)
        #expect(state.currentMatchIndex == 0)
    }

    // MARK: - Offset-alignment invariant

    @Test func matchOffsetsAreValidIndicesIntoParsedString() {
        let state = makeState()
        let cache = HighlightingMarkdownCache()
        let corpus = [
            "# Heading\n\nsome **bold** text with foo",
            "- one foo\n- two foo\n\n`inline foo`",
            "| col | foo |\n| --- | --- |\n| 1 | foo |",
            "plain foo and foo again",
            "> quoted foo\n\n```\ncode foo\n```",
        ]

        for doc in corpus {
            state.updateDocument(markdown: doc, using: cache)

            // The render-side parser overlays highlights on cache.attributedString, while matches
            // are computed from cache.plainText — they must describe the same character sequence.
            let parsedCount = cache.attributedString.characters.count
            #expect(cache.plainText.count == parsedCount)

            state.updateQuery("foo")
            for match in state.matches {
                #expect(match.lowerBound >= 0)
                #expect(match.upperBound <= parsedCount)
                #expect(match.lowerBound < match.upperBound)
            }
        }
    }

    // MARK: - currentMatchFraction

    @Test func currentMatchFractionIsNilWithoutMatches() {
        let state = makeState()
        state.updateDocument(markdown: "", using: HighlightingMarkdownCache())
        state.updateQuery("anything")
        #expect(state.currentMatchFraction == nil)
    }

    @Test func currentMatchFractionStaysWithinUnitInterval() {
        // A match in each block kind that drives a different localFraction branch.
        let docs = [
            "plain paragraph with foo in it",
            "# Heading with foo\n\nfollowed by body text",
            "```\ncode line one\ncode foo line\n```",
            "| col a | col b |\n| --- | --- |\n| 1 | foo |\n| 3 | 4 |",
            "> a block quote mentioning foo",
        ]

        for doc in docs {
            let state = makeState()
            state.updateDocument(markdown: doc, using: HighlightingMarkdownCache())
            state.updateQuery("foo")

            guard let fraction = state.currentMatchFraction else {
                Issue.record("expected a fraction for: \(doc)")
                continue
            }
            #expect(fraction.isFinite)
            #expect(fraction >= 0)
            #expect(fraction <= 1)
        }
    }

    // MARK: - topLevelBlockRuns

    @Test func tableCollapsesToOneBlock() throws {
        let cache = HighlightingMarkdownCache()
        try cache.prepare(markdown: """
            | a | b |
            | --- | --- |
            | 1 | 2 |
            | 3 | 4 |
            """)

        let runs = SearchState.topLevelBlockRuns(in: cache.attributedString)
        let tableRuns = runs.filter { run in
            if case .table = run.intent?.kind { return true }
            return false
        }

        // One block for the whole table, not one per cell.
        #expect(tableRuns.count == 1)
        // Header row + two data rows; the `---` delimiter line is not a row.
        #expect(tableRuns.first?.tableRowRanges.count == 3)
    }

    @Test func blockRunsSeparateAdjacentBlockKinds() throws {
        let cache = HighlightingMarkdownCache()
        try cache.prepare(markdown: """
            # Title

            A paragraph.

            | a | b |
            | --- | --- |
            | 1 | 2 |
            """)

        let runs = SearchState.topLevelBlockRuns(in: cache.attributedString)
        // Heading, paragraph, and table are distinct top-level blocks.
        #expect(runs.count >= 3)
        let tableRuns = runs.filter { run in
            if case .table = run.intent?.kind { return true }
            return false
        }
        #expect(tableRuns.count == 1)
    }

    // MARK: - Width-aware wrap estimate

    @Test func charactersPerLineTracksWidthAndFont() {
        let narrow = Theme.default.blockLayout(fontSize: 16, contentWidth: 320)
        let wide = Theme.default.blockLayout(fontSize: 16, contentWidth: 1280)
        let bigFont = Theme.default.blockLayout(fontSize: 32, contentWidth: 1280)

        #expect(wide.charactersPerLine() > narrow.charactersPerLine())   // wider fits more
        #expect(bigFont.charactersPerLine() < wide.charactersPerLine())  // bigger glyphs fit fewer
        // Unmeasured width falls back to the fixed estimate.
        #expect(Theme.default.blockLayout(fontSize: 16).charactersPerLine() == 72)
    }

    @Test func wrapWidthShiftsTheEstimatedFraction() throws {
        // A long single-line paragraph (which wraps differently by width) followed by a heading
        // that holds the only match. Narrower content wraps the paragraph into more lines, inflating
        // the weight before the heading and pushing the heading's estimated fraction higher.
        let paragraph = String(repeating: "word ", count: 80)
        let doc = paragraph + "\n\n# Tail heading foo"

        let narrow = makeState(contentWidth: 320)
        narrow.updateDocument(markdown: doc, using: HighlightingMarkdownCache())
        narrow.updateQuery("foo")

        let wide = makeState(contentWidth: 2000)
        wide.updateDocument(markdown: doc, using: HighlightingMarkdownCache())
        wide.updateQuery("foo")

        let narrowFraction = try #require(narrow.currentMatchFraction)
        let wideFraction = try #require(wide.currentMatchFraction)
        #expect(narrowFraction > wideFraction)
    }
}
