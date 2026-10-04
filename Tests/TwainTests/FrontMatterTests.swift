import Testing
import Foundation
import Textual
@testable import Twain
@testable import TwainRendering

struct FrontMatterExtractionTests {
    @Test func documentWithoutFrontMatterIsUntouched() {
        let markdown = "# Title\n\ntext"
        let result = FrontMatter.extract(from: markdown)
        #expect(result.frontMatter == nil)
        #expect(result.body == markdown)
    }

    @Test func mappingIsSplitOffTheBody() {
        let result = FrontMatter.extract(
            from: "---\nname: grill-me\ndescription: Interview the user\n---\n\n# Body"
        )
        #expect(result.frontMatter == FrontMatter(entries: [
            .init(key: "name", value: .scalar("grill-me")),
            .init(key: "description", value: .scalar("Interview the user")),
        ]))
        #expect(result.body == "\n# Body")
    }

    @Test func thematicBreakOpeningIsNotFrontMatter() {
        let markdown = "---\n\nSome paragraph\n\n---\n\nMore"
        let result = FrontMatter.extract(from: markdown)
        #expect(result.frontMatter == nil)
        #expect(result.body == markdown)
    }

    @Test func unterminatedBlockIsNotFrontMatter() {
        let markdown = "---\nname: x\n\n# Title"
        #expect(FrontMatter.extract(from: markdown).frontMatter == nil)
        #expect(FrontMatter.extract(from: markdown).body == markdown)
    }

    @Test func closingWithDotsIsAccepted() {
        let result = FrontMatter.extract(from: "---\nname: x\n...\nbody")
        #expect(result.frontMatter?.entries == [.init(key: "name", value: .scalar("x"))])
        #expect(result.body == "body")
    }

    @Test func crlfAndBomAreHandled() {
        let result = FrontMatter.extract(from: "\u{FEFF}---\r\nname: x\r\ntags: [a, b]\r\n---\r\n# Title")
        #expect(result.frontMatter?.entries == [
            .init(key: "name", value: .scalar("x")),
            .init(key: "tags", value: .sequence([.scalar("a"), .scalar("b")])),
        ])
        #expect(result.body == "# Title")
    }

    @Test func emptyBlockIsEmptyFrontMatter() {
        let result = FrontMatter.extract(from: "---\n---\nbody")
        #expect(result.frontMatter == FrontMatter(entries: []))
        #expect(result.body == "body")
    }

    @Test func colonWithoutSpaceDoesNotMakeAKey() {
        #expect(FrontMatter.extract(from: "---\nhttp://example.com\n---\n").frontMatter == nil)
    }

    @Test func trailingWhitespaceOnDelimitersIsAllowed() {
        let result = FrontMatter.extract(from: "---  \nname: x\n---\t\nbody")
        #expect(result.frontMatter?.entries.count == 1)
        #expect(result.body == "body")
    }
}

struct FrontMatterYAMLTests {
    private func entries(_ yaml: String) throws -> [FrontMatter.Entry] {
        try #require(FrontMatter.extract(from: "---\n\(yaml)\n---\n").frontMatter).entries
    }

    private func value(_ yaml: String) throws -> FrontMatter.Value {
        try #require(entries(yaml).first).value
    }

    @Test func quotedScalarsLoseTheirQuotes() throws {
        #expect(try value("a: \"hello \\\"world\\\"\"") == .scalar("hello \"world\""))
        #expect(try value("a: 'it''s'") == .scalar("it's"))
        #expect(try value("a: '*'") == .scalar("*"))
    }

    @Test func trailingCommentsAreStripped() throws {
        #expect(try value("a: value # note") == .scalar("value"))
        #expect(try value("a: '# not a comment'") == .scalar("# not a comment"))
        #expect(try value("a: x#y") == .scalar("x#y"))
        #expect(try value("a: #comment only") == .scalar(""))
    }

    @Test func commentLinesAreSkipped() throws {
        #expect(try entries("# leading\na: 1\n# between\nb: 2").map(\.key) == ["a", "b"])
    }

    @Test func foldedBlockScalarJoinsLines() throws {
        let parsed = try entries(
            "description: >-\n  Open Markdown files\n  in Twain.\n\n  Second paragraph.\nlicense: MIT"
        )
        #expect(parsed[0].value == .scalar("Open Markdown files in Twain.\nSecond paragraph."))
        #expect(parsed[1] == .init(key: "license", value: .scalar("MIT")))
    }

    @Test func literalBlockScalarKeepsLines() throws {
        #expect(
            try value("script: |\n  line one\n    indented\n  line three")
                == .scalar("line one\n  indented\nline three")
        )
    }

    @Test func plainScalarContinuationLinesFold() throws {
        #expect(try value("description: first line\n  second line") == .scalar("first line second line"))
    }

    @Test func nestedMappingsAndSequences() throws {
        let parsed = try entries("""
            metadata:
              author: Vincent Bruijn
              homepage: https://github.com/y-a-v-a/twain
            children:
            - /a
            - /b
            tools:
              - Read
              - Grep
            """)
        #expect(parsed.map(\.key) == ["metadata", "children", "tools"])
        #expect(parsed[0].value == .mapping([
            .init(key: "author", value: .scalar("Vincent Bruijn")),
            .init(key: "homepage", value: .scalar("https://github.com/y-a-v-a/twain")),
        ]))
        #expect(parsed[1].value == .sequence([.scalar("/a"), .scalar("/b")]))
        #expect(parsed[2].value == .sequence([.scalar("Read"), .scalar("Grep")]))
    }

    @Test func sequenceOfMappings() throws {
        let parsed = try value("""
            hooks:
              PreToolUse:
                - matcher: Bash
                  hooks:
                    - type: command
                      command: ./check.sh
            """)
        #expect(parsed == .mapping([
            .init(key: "PreToolUse", value: .sequence([
                .mapping([
                    .init(key: "matcher", value: .scalar("Bash")),
                    .init(key: "hooks", value: .sequence([
                        .mapping([
                            .init(key: "type", value: .scalar("command")),
                            .init(key: "command", value: .scalar("./check.sh")),
                        ]),
                    ])),
                ]),
            ])),
        ]))
    }

    @Test func flowSequenceItems() throws {
        #expect(try value("tags: [a, \"b, c\", 'd']") == .sequence([.scalar("a"), .scalar("b, c"), .scalar("d")]))
        #expect(try value("tags: []") == .sequence([]))
    }

    @Test func emptyValueIsAnEmptyScalar() throws {
        #expect(try value("a:") == .scalar(""))
    }

    @Test func unparseableNestedBlockIsKeptAsText() throws {
        #expect(try value("weird:\n  - item\n  key: value") == .scalar("- item\nkey: value"))
    }

    @Test func quotedKeysAreUnquoted() throws {
        #expect(try entries("\"my key\": v").first?.key == "my key")
    }

    @Test func valuesContainingColonsStayWhole() throws {
        #expect(try value("title: Twain: a viewer") == .scalar("Twain: a viewer"))
    }
}

struct FrontMatterDisplayTests {
    @Test func nestedValuesRenderAsIndentedYAMLLines() {
        let value = FrontMatter.Value.mapping([
            .init(key: "PreToolUse", value: .sequence([
                .mapping([
                    .init(key: "matcher", value: .scalar("Bash")),
                    .init(key: "hooks", value: .sequence([
                        .mapping([.init(key: "type", value: .scalar("command"))]),
                    ])),
                ]),
            ])),
        ])
        #expect(value.displayText == """
            PreToolUse:
              - matcher: Bash
                hooks:
                  - type: command
            """)
    }

    @Test func scalarSequenceRendersOneItemPerLine() {
        #expect(FrontMatter.Value.sequence([.scalar("a"), .scalar("b")]).displayText == "- a\n- b")
    }

    @Test func multiLineScalarInsideAMappingIsIndentedUnderItsKey() {
        let value = FrontMatter.Value.mapping([.init(key: "k", value: .scalar("one\ntwo"))])
        #expect(value.displayText == "k:\n  one\n  two")
    }

    @Test func bareURLsBecomeLinks() {
        #expect(FrontMatter.Value.scalar("https://example.com/x").linkURL == URL(string: "https://example.com/x"))
        #expect(FrontMatter.Value.scalar("see https://example.com").linkURL == nil)
        #expect(FrontMatter.Value.scalar("MIT").linkURL == nil)
    }
}

@MainActor
struct FrontMatterRenderingTests {
    private let skill = """
        ---
        name: grill-me
        description: Interview the user
        homepage: https://example.com
        ---

        # Grill me

        Body text.
        """
    private let skillTableText = "namegrill-medescriptionInterview the userhomepagehttps://example.com"

    @Test func tableIsOneBlockWithTwoColumnsAndARowPerEntry() throws {
        let frontMatter = try #require(FrontMatter.extract(from: skill).frontMatter)
        let table = frontMatter.tableAttributedString()

        let blocks = SearchState.topLevelBlockRuns(in: table)
        #expect(blocks.count == 1)
        guard case .table(let columns)? = blocks.first?.intent?.kind else {
            Issue.record("front matter did not produce a table block")
            return
        }
        #expect(columns.count == 2)
        #expect(blocks.first?.tableRowRanges.count == 3)
        #expect(String(table.characters) == skillTableText)
    }

    @Test func cellsCarryTheFrontMatterMarkerAndLinkBareURLs() throws {
        let frontMatter = try #require(FrontMatter.extract(from: skill).frontMatter)
        let table = frontMatter.tableAttributedString()
        #expect(table.runs.allSatisfy { $0.twain.frontMatter == true })

        let linked = table.runs.filter { $0.link != nil }
        #expect(linked.count == 1)
        #expect(linked.first?.link == URL(string: "https://example.com"))
    }

    @Test func parserPrependsTheTableAndDropsTheDelimiters() throws {
        let parsed = try FrontMatterParser(base: AttributedStringMarkdownParser(baseURL: nil))
            .attributedString(for: skill)
        let text = String(parsed.characters)
        #expect(text.hasPrefix(skillTableText))
        #expect(!text.contains("---"))

        let parts = parsed.splitFrontMatter()
        #expect(String(parts.frontMatter.characters) == skillTableText)
        #expect(String(parts.body.characters) == "Grill meBody text.")
    }

    @Test func documentWithoutFrontMatterParsesAsBefore() throws {
        let markdown = "# Title\n\n---\n\nText"
        let plain = try AttributedStringMarkdownParser(baseURL: nil).attributedString(for: markdown)
        let wrapped = try FrontMatterParser(base: AttributedStringMarkdownParser(baseURL: nil))
            .attributedString(for: markdown)
        #expect(plain == wrapped)
        #expect(wrapped.splitFrontMatter().frontMatter.characters.isEmpty)
        #expect(wrapped.splitFrontMatter().body == plain)
    }

    @Test func emptyFrontMatterRendersNothing() throws {
        let parsed = try FrontMatterParser(base: AttributedStringMarkdownParser(baseURL: nil))
            .attributedString(for: "---\n---\n# Title")
        #expect(String(parsed.characters) == "Title")
    }

    @Test func emptyValueCellStillOccupiesItsRow() {
        let table = FrontMatter(entries: [.init(key: "a", value: .scalar(""))]).tableAttributedString()
        #expect(table.runs.count == 2)
    }

    @Test func searchFindsFrontMatterTextAtAlignedOffsets() throws {
        let cache = HighlightingMarkdownCache()
        try cache.prepare(markdown: skill)
        #expect(cache.plainText.hasPrefix(skillTableText))
        #expect(SearchState.findMatches(of: "Interview", in: cache.plainText) == [23..<32])
    }

    @Test func taskListExpansionLeavesTheTableAlone() throws {
        let cache = HighlightingMarkdownCache()
        try cache.prepare(markdown: "---\nnote: \"[x] literal\"\n---\n- [x] done")
        #expect(cache.plainText == "note[x] literal☑ done")
    }
}
