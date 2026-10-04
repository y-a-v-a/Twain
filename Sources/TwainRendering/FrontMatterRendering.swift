import SwiftUI
import Textual

// MARK: - Attributes

extension AttributeScopes {
    /// Attributes Twain adds to rendered documents on top of Foundation's and Textual's.
    public struct TwainAttributes: AttributeScope {
        /// Marks the runs of the front-matter table that `FrontMatterParser` prepends, so the
        /// renderer can hand them to their own `StructuredText` instance.
        public enum FrontMatterAttribute: AttributedStringKey {
            public typealias Value = Bool
            public static let name = "Twain.FrontMatter"
        }

        public let frontMatter: FrontMatterAttribute
    }

    public var twain: TwainAttributes.Type { TwainAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.TwainAttributes, T>
    ) -> T {
        self[T.self]
    }
}

// MARK: - Table

extension FrontMatter {
    /// A key/value table with one row per top-level entry, carrying the presentation intents
    /// Foundation's Markdown parser emits for a GFM table so Textual renders it with the
    /// document's table style. Empty when there are no entries.
    public func tableAttributedString() -> AttributedString {
        var result = AttributedString()
        guard !entries.isEmpty else { return result }

        // Identities count down from -1: Foundation numbers its intents up from 1, so the table
        // can never be mistaken for a body block when the search estimator groups runs.
        var identity = 0
        func nextIdentity() -> Int {
            identity -= 1
            return identity
        }

        let table = PresentationIntent(
            .table(columns: [.init(alignment: .left), .init(alignment: .left)]),
            identity: nextIdentity()
        )
        for (rowIndex, entry) in entries.enumerated() {
            let row = PresentationIntent(.tableRow(rowIndex: rowIndex), identity: nextIdentity(), parent: table)
            result.append(Self.cell(entry.key, column: 0, row: row, identity: nextIdentity()))
            result.append(Self.cell(
                entry.value.displayText,
                column: 1,
                row: row,
                identity: nextIdentity(),
                link: entry.value.linkURL
            ))
        }
        return result
    }

    private static func cell(
        _ text: String,
        column: Int,
        row: PresentationIntent,
        identity: Int,
        link: URL? = nil
    ) -> AttributedString {
        var attributes = AttributeContainer()
        attributes.presentationIntent = PresentationIntent(
            .tableCell(columnIndex: column),
            identity: identity,
            parent: row
        )
        attributes.twain.frontMatter = true
        attributes.link = link
        // An empty run carries no attributes, so an empty cell would vanish from its row.
        return AttributedString(text.isEmpty ? "\u{00A0}" : text, attributes: attributes)
    }
}

// MARK: - Parsing

/// Wraps a Markdown parser so a leading YAML front-matter block renders as a key/value table,
/// the way GitHub shows it, instead of as literal Markdown.
public struct FrontMatterParser<Base: MarkupParser>: MarkupParser {
    private let base: Base

    public init(base: Base) {
        self.base = base
    }

    public func attributedString(for input: String) throws -> AttributedString {
        let (frontMatter, body) = FrontMatter.extract(from: input)
        let document = try base.attributedString(for: body)
        guard let frontMatter else { return document }
        return frontMatter.tableAttributedString() + document
    }
}

extension AttributedString {
    /// The front-matter table this document starts with (empty when it has none) and the rest.
    public func splitFrontMatter() -> (frontMatter: AttributedString, body: AttributedString) {
        let end = runs.first { $0.twain.frontMatter != true }?.range.lowerBound ?? endIndex
        return (AttributedString(self[startIndex..<end]), AttributedString(self[end..<endIndex]))
    }
}

/// Hands one half of a `FrontMatterParser` result to a `StructuredText`.
struct FrontMatterSliceParser: MarkupParser {
    enum Slice {
        case frontMatter
        case body
    }

    let base: any MarkupParser
    let slice: Slice

    func attributedString(for input: String) throws -> AttributedString {
        let parts = try base.attributedString(for: input).splitFrontMatter()
        return slice == .frontMatter ? parts.frontMatter : parts.body
    }
}

// MARK: - View

/// `StructuredText` for a whole document. The front-matter table, if any, renders in its own
/// instance: Textual bolds row 0 of every table as its header and gives cell styles no way to
/// tell a header-less table apart, so the key/value table takes a key-column cell style here.
public struct DocumentText: View {
    private let markup: String
    private let parser: any MarkupParser
    private let theme: Theme

    public init(_ markup: String, parser: any MarkupParser, theme: Theme) {
        self.markup = markup
        self.parser = parser
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StructuredText(markup, parser: FrontMatterSliceParser(base: parser, slice: .frontMatter))
                .textual.tableStyle(
                    ThemedTableStyle(theme: theme, trailingSpacing: theme.styleLayout.tableBottomSpacing)
                )
                .textual.tableCellStyle(ThemedTableCellStyle(theme: theme, emphasis: .keyColumn))
            StructuredText(markup, parser: FrontMatterSliceParser(base: parser, slice: .body))
        }
    }
}
