import Testing
import Foundation
@testable import Twain

@MainActor
struct SearchStateTests {
    private func makeState() -> SearchState {
        SearchState(layout: Theme.default.blockLayout(fontSize: 16))
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
}
